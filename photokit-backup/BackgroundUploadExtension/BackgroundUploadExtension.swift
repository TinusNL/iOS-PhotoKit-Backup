import ExtensionFoundation
import Foundation
import Photos
import Synchronization

/// BackgroundUploadURLBase in Info.plist is only Apple's network check. Upload jobs use the server address saved in the app.
@main
final class BackgroundUploadExtension: PHBackgroundResourceUploadJobExtension, @unchecked Sendable {
  private let cancelled = Atomic<Bool>(false)
  private let cursorKey = "libraryCursor"

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
      let more = try await enqueueMissingUploads(settings: settings)
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
    for index in 0..<jobs.count {
      if cancelled.load(ordering: .acquiring) { return }
      let job = jobs.object(at: index)
      if isPermanent(job.error) {
        recordFailure(for: job)
        try await acknowledge(job, library: library)
        continue
      }
      try await library.performChanges {
        PHAssetResourceUploadJobChangeRequest(for: job)?.retry(destination: nil)
      }
    }
  }

  private func acknowledgeFinishedJobs() async throws {
    let jobs = PHAssetResourceUploadJob.fetchJobs(action: .acknowledge, options: nil)
    let library = PHPhotoLibrary.shared()
    for index in 0..<jobs.count {
      if cancelled.load(ordering: .acquiring) { return }
      let job = jobs.object(at: index)
      if job.state == .succeeded {
        clearFailure(for: job)
      } else if job.state == .failed, isPermanent(job.error) {
        recordFailure(for: job)
      }
      try await acknowledge(job, library: library)
    }
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
    let batchStart = cursor
    let inflight = inflightKeys()
    var batch: [LibraryUpload] = []
    while cursor < assets.count && batch.count < 100 {
      if cancelled.load(ordering: .acquiring) {
        return true
      }
      let asset = assets.object(at: cursor)
      cursor += 1
      for upload in LibraryScanner.uploads(
        for: asset, uploadLivePhotoMovies: settings.uploadLivePhotoMovies)
      {
        if inflight.contains(upload.expected.key) || FailureLedger.shouldSkip(upload.expected.key) {
          continue
        }
        batch.append(upload)
      }
    }

    if batch.isEmpty {
      AppGroup.defaults.set(0, forKey: cursorKey)
      ChangeTokenStore.save(library.currentChangeToken)
      return !inflight.isEmpty
    }

    let stored = try await BackupClient(baseURL: settings.serverURL, apiKey: settings.apiKey)
      .lookup(batch.map(\.expected))
    let missingKeys = Set(
      PendingUploads.missing(expected: batch.map(\.expected), uploaded: stored).map(\.key))
    var created = 0

    for upload in batch where missingKeys.contains(upload.expected.key) {
      if cancelled.load(ordering: .acquiring) {
        AppGroup.defaults.set(batchStart, forKey: cursorKey)
        return true
      }
      guard let request = UploadRequest.make(settings: settings, item: upload.expected) else {
        continue
      }
      do {
        try await library.performChanges {
          _ = PHAssetResourceUploadJobChangeRequest.creationRequestForJob(
            destination: request,
            resource: upload.resource
          )
        }
        created += 1
      } catch {
        if isLimitExceeded(error) {
          AppGroup.defaults.set(batchStart, forKey: cursorKey)
          throw LimitExceeded()
        }
        throw error
      }
    }

    AppGroup.defaults.set(cursor, forKey: cursorKey)
    if cursor >= assets.count {
      AppGroup.defaults.set(0, forKey: cursorKey)
      ChangeTokenStore.save(library.currentChangeToken)
      return created > 0 || !inflight.isEmpty
    }
    return true
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
