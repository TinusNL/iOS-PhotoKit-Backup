import ExtensionFoundation
import Foundation
import Photos
import Synchronization
import UserNotifications

/// BackgroundUploadURLBase in Info.plist is only Apple's network check. Upload jobs use the server address saved in the app.
@main
final class BackgroundUploadExtension: PHBackgroundResourceUploadJobExtension, @unchecked Sendable {
  private let cancelled = Atomic<Bool>(false)
  private let cursorKey = "libraryCursorOldest"

  required init() {}

  func processJobs() async -> PHBackgroundResourceUploadProcessingResult {
    if cancelled.load(ordering: .acquiring) {
      return .processing
    }
    guard BackupSettings.hasServer else {
      return .completed
    }
    guard let settings = BackupSettings.load() else {
      return .processing
    }

    do {
      if !settings.uploadLivePhotoMovies {
        try cancelPairedVideoJobs()
      }
      try await retryFailedJobs()
      try await acknowledgeFinishedJobs()
      await deliverUploadFailures()
      let more = try await enqueueMissingUploads(settings: settings)
      if !more {
        await deliverUploadSummary(force: true)
        UploadSummary.reset()
        UploadFailureNotice.reset()
      }
      return more ? .processing : .completed
    } catch is LimitExceeded {
      return .processing
    } catch {
      return .failure
    }
  }

  func willTerminate() async {
    cancelled.store(true, ordering: .releasing)
  }

  private func retryFailedJobs() async throws {
    let jobs = PHAssetResourceUploadJob.fetchJobs(action: .retry, options: nil)
    let library = PHPhotoLibrary.shared()
    var failed: [String] = []
    for index in 0..<jobs.count {
      if cancelled.load(ordering: .acquiring) {
        UploadFailureNotice.record(failed)
        return
      }
      let job = jobs.object(at: index)
      if isPermanent(job.error) {
        recordFailure(for: job)
        if countsAsFile(job) {
          failed.append(finishedFilename(for: job))
        }
        try await acknowledge(job, library: library)
        continue
      }
      try await library.performChanges {
        PHAssetResourceUploadJobChangeRequest(for: job)?.retry(destination: nil)
      }
    }
    UploadFailureNotice.record(failed)
  }

  private func acknowledgeFinishedJobs() async throws {
    let jobs = PHAssetResourceUploadJob.fetchJobs(action: .acknowledge, options: nil)
    let library = PHPhotoLibrary.shared()
    var finished: [String] = []
    var failed: [String] = []
    for index in 0..<jobs.count {
      if cancelled.load(ordering: .acquiring) {
        UploadSummary.record(finished)
        UploadFailureNotice.record(failed)
        await deliverUploadSummary(force: false)
        return
      }
      let job = jobs.object(at: index)
      if job.state == .succeeded {
        clearFailure(for: job)
        if countsAsFile(job) {
          finished.append(finishedFilename(for: job))
        }
      } else if job.state == .failed {
        if isPermanent(job.error) {
          recordFailure(for: job)
        }
        if countsAsFile(job) {
          failed.append(finishedFilename(for: job))
        }
      }
      try await acknowledge(job, library: library)
    }
    UploadSummary.record(finished)
    UploadFailureNotice.record(failed)
    await deliverUploadSummary(force: false)
  }

  private func deliverUploadSummary(force: Bool) async {
    guard let message = UploadSummary.messageIfDue(force: force) else { return }
    await deliver(message, identifier: "photokit-backup-summary")
  }

  private func deliverUploadFailures() async {
    guard let message = UploadFailureNotice.message() else { return }
    await deliver(message, identifier: "photokit-backup-failure")
  }

  private func deliver(_ message: String, identifier: String) async {
    let content = UNMutableNotificationContent()
    content.title = "PhotoKit Backup"
    content.body = message
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    let center = UNUserNotificationCenter.current()
    center.removeDeliveredNotifications(withIdentifiers: [identifier])
    try? await center.add(request)
  }

  /// A Live Photo uploads its still and its movie. The still is the file the notification counts.
  private func countsAsFile(_ job: PHAssetResourceUploadJob) -> Bool {
    guard let resource = PHAssetResource.assetResource(forUploadJob: job) else { return true }
    return resource.type != .pairedVideo
  }

  private func finishedFilename(for job: PHAssetResourceUploadJob) -> String {
    guard let resource = PHAssetResource.assetResource(forUploadJob: job),
      let filename = resource.filename, !filename.isEmpty
    else {
      return ""
    }
    return filename
  }

  private func enqueueMissingUploads(settings: BackupSettings) async throws -> Bool {
    let library = PHPhotoLibrary.shared()
    resetCursorIfLibraryChanged(library: library)

    let options = PHFetchOptions()
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
    let assets = PHAsset.fetchAssets(with: options)
    var cursor = AppGroup.defaults.integer(forKey: cursorKey)
    if cursor < 0 || cursor > assets.count {
      cursor = 0
    }

    let inflight = inflightKeys()
    let client = BackupClient(baseURL: settings.serverURL, apiKey: settings.apiKey)
    var scanned = 0

    while cursor < assets.count && scanned < 400 {
      if cancelled.load(ordering: .acquiring) {
        AppGroup.defaults.set(cursor, forKey: cursorKey)
        return true
      }
      let sliceEnd = min(cursor + 40, assets.count)
      var grouped: [(index: Int, uploads: [LibraryUpload])] = []
      var expected: [ExpectedUpload] = []
      for index in cursor..<sliceEnd {
        let uploads = LibraryScanner.uploads(
          for: assets.object(at: index),
          uploadLivePhotoMovies: settings.uploadLivePhotoMovies
        )
        grouped.append((index, uploads))
        expected.append(contentsOf: uploads.map(\.expected))
      }
      scanned += sliceEnd - cursor
      let stored = expected.isEmpty ? [:] : try await client.lookup(expected)
      let missingKeys = Set(
        PendingUploads.missing(expected: expected, uploaded: stored).map(\.key))

      for group in grouped {
        let missing = group.uploads.filter {
          missingKeys.contains($0.expected.key) && !FailureLedger.shouldSkip($0.expected.key)
        }
        if missing.isEmpty {
          continue
        }
        AppGroup.defaults.set(group.index, forKey: cursorKey)
        let upload = missing.first { !inflight.contains($0.expected.key) } ?? missing[0]
        cancelJobs(except: upload.expected.key)
        guard !inflight.contains(upload.expected.key),
          let request = UploadRequest.make(settings: settings, item: upload.expected)
        else {
          return true
        }
        do {
          try await library.performChanges {
            _ = PHAssetResourceUploadJobChangeRequest.creationRequestForJob(
              destination: request,
              resource: upload.resource
            )
          }
        } catch {
          if isLimitExceeded(error) {
            throw LimitExceeded()
          }
          throw error
        }
        return true
      }

      cursor = sliceEnd
      AppGroup.defaults.set(cursor, forKey: cursorKey)
    }

    if cursor >= assets.count {
      AppGroup.defaults.set(0, forKey: cursorKey)
      ChangeTokenStore.save(library.currentChangeToken)
      return !inflight.isEmpty
    }
    return true
  }

  private func cancelJobs(except key: String) {
    let jobs = PHAssetResourceUploadJob.fetchJobs(action: .process, options: nil)
    let library = PHPhotoLibrary.shared()
    for index in 0..<jobs.count {
      let job = jobs.object(at: index)
      guard uploadKey(for: job) != key else { continue }
      try? library.performChangesAndWait {
        PHAssetResourceUploadJobChangeRequest(for: job)?.cancel()
      }
    }
  }

  private func cancelPairedVideoJobs() throws {
    let jobs = PHAssetResourceUploadJob.fetchJobs(action: .process, options: nil)
    let library = PHPhotoLibrary.shared()
    for index in 0..<jobs.count {
      let job = jobs.object(at: index)
      guard let resource = PHAssetResource.assetResource(forUploadJob: job),
        resource.type == .pairedVideo
      else {
        continue
      }
      do {
        try library.performChangesAndWait {
          PHAssetResourceUploadJobChangeRequest(for: job)?.cancel()
        }
      } catch {
        continue
      }
    }
  }

  private func acknowledge(_ job: PHAssetResourceUploadJob, library: PHPhotoLibrary) async throws {
    try await library.performChanges {
      PHAssetResourceUploadJobChangeRequest(for: job)?.acknowledge()
    }
  }

  private func inflightKeys() -> Set<String> {
    let jobs = PHAssetResourceUploadJob.fetchJobs(action: .process, options: nil)
    var keys: Set<String> = []
    for index in 0..<jobs.count {
      let job = jobs.object(at: index)
      if let key = uploadKey(for: job) {
        keys.insert(key)
      }
    }
    return keys
  }

  private func recordFailure(for job: PHAssetResourceUploadJob) {
    if let key = uploadKey(for: job) {
      FailureLedger.record(key)
    }
  }

  private func clearFailure(for job: PHAssetResourceUploadJob) {
    if let key = uploadKey(for: job) {
      FailureLedger.clear(key)
    }
  }

  private func uploadKey(for job: PHAssetResourceUploadJob) -> String? {
    guard let resource = PHAssetResource.assetResource(forUploadJob: job) else { return nil }
    let type: String
    switch resource.type {
    case .photo:
      type = "photo"
    case .pairedVideo:
      type = "pairedVideo"
    case .video:
      type = "video"
    default:
      return nil
    }
    return "\(resource.assetLocalIdentifier)|\(type)"
  }

  private func resetCursorIfLibraryChanged(library: PHPhotoLibrary) {
    guard let token = ChangeTokenStore.load() else { return }
    do {
      let changes = try library.fetchPersistentChanges(since: token)
      var changed = false
      for _ in changes {
        changed = true
        break
      }
      if changed {
        AppGroup.defaults.set(0, forKey: cursorKey)
      }
    } catch {
      if isTokenExpired(error) {
        ChangeTokenStore.clear()
        AppGroup.defaults.set(0, forKey: cursorKey)
      }
    }
  }

  private func isPermanent(_ error: Error?) -> Bool {
    guard let error else { return false }
    let code = (error as? URLError)?.code ?? URLError.Code(rawValue: (error as NSError).code)
    switch code {
    case .badServerResponse, .userAuthenticationRequired, .noPermissionsToReadFile:
      return true
    default:
      return false
    }
  }

  private func isLimitExceeded(_ error: Error) -> Bool {
    let nsError = error as NSError
    return nsError.domain == PHPhotosErrorDomain
      && nsError.code == PHPhotosError.limitExceeded.rawValue
  }

  private func isTokenExpired(_ error: Error) -> Bool {
    let nsError = error as NSError
    return nsError.domain == PHPhotosErrorDomain
      && nsError.code == PHPhotosError.persistentChangeTokenExpired.rawValue
  }
}

private struct LimitExceeded: Error {}

private enum ChangeTokenStore {
  private static let key = "persistentChangeToken"

  static func load() -> PHPersistentChangeToken? {
    guard let data = AppGroup.defaults.data(forKey: key) else { return nil }
    return try? NSKeyedUnarchiver.unarchivedObject(
      ofClass: PHPersistentChangeToken.self, from: data)
  }

  static func save(_ token: PHPersistentChangeToken) {
    guard
      let data = try? NSKeyedArchiver.archivedData(
        withRootObject: token, requiringSecureCoding: true)
    else {
      return
    }
    AppGroup.defaults.set(data, forKey: key)
  }

  static func clear() {
    AppGroup.defaults.removeObject(forKey: key)
  }
}
