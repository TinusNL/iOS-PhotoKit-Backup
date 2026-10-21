import Foundation
import Photos

struct FastBackupItemProgress: Equatable, Sendable {
  var sent: Int64
  var total: Int64

  var fraction: Double {
    guard total > 0 else { return 0 }
    return min(1, Double(sent) / Double(total))
  }

  var percent: Int {
    FastBackupCopy.percent(sent, total)
  }
}

struct FastProgressEvent: Sendable {
  var resourceKey: String
  var sent: Int64
  var total: Int64
}

struct FastTransferResult: Sendable {
  var uploaded: [ExpectedUpload]
  var itemBytes: Int64
}

nonisolated enum FastBackupCopy {
  static func waitingLine(for items: [ListedUpload]) -> String {
    "\(mediaPhrase(items)) waiting to upload"
  }

  static func uploadingLine(for items: [ListedUpload]) -> String {
    "Uploading \(mediaPhrase(items))"
  }

  static func completedLine(done: Int, total: Int) -> String {
    let noun = total == 1 ? "item" : "items"
    return "\(done) of \(total) \(noun) completed"
  }

  static func uploadingCount(_ count: Int) -> String {
    count == 1 ? "1 uploading" : "\(count) uploading"
  }

  static func percent(_ sent: Int64, _ total: Int64) -> Int {
    guard total > 0 else { return 0 }
    return min(100, Int((Double(sent) / Double(total) * 100).rounded()))
  }

  static func mediaPhrase(_ items: [ListedUpload]) -> String {
    let videos = items.filter(isVideo).count
    let photos = items.count - videos
    switch (photos, videos) {
    case (0, 0):
      return "0 items"
    case (0, 1):
      return "1 video"
    case (0, let count):
      return "\(count) videos"
    case (1, 0):
      return "1 photo"
    case (let count, 0):
      return "\(count) photos"
    case (1, 1):
      return "1 photo and 1 video"
    case (1, let count):
      return "1 photo and \(count) videos"
    case (let count, 1):
      return "\(count) photos and 1 video"
    case (let photos, let videos):
      return "\(photos) photos and \(videos) videos"
    }
  }

  static func isVideo(_ item: ListedUpload) -> Bool {
    if item.isLivePhoto { return false }
    let ext = URL(fileURLWithPath: item.title).pathExtension.lowercased()
    return videoExtensions.contains(ext)
  }

  private static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi"]
}

enum FastBackupPhase: Equatable, Sendable {
  case idle
  case running
}

nonisolated enum FastUploader {
  static func transfer(
    assetId: String,
    listedID: String,
    settings: BackupSettings,
    skipKeys: Set<String>,
    onProgress: @escaping @Sendable (FastProgressEvent) -> Void,
    onBodiesSent: @escaping @Sendable (FastProgressEvent) -> Void
  ) async throws -> FastTransferResult {
    let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
    guard let asset = assets.firstObject else {
      return FastTransferResult(uploaded: [], itemBytes: 0)
    }
    let selected = LibraryScanner.uploads(
      for: asset, uploadLivePhotoMovies: settings.uploadLivePhotoMovies
    ).filter { upload in
      if skipKeys.contains(upload.expected.key) { return false }
      if listedID == assetId { return true }
      return upload.expected.key == listedID
    }
    var uploaded: [ExpectedUpload] = []
    var itemBytes: Int64 = 0
    for (offset, upload) in selected.enumerated() {
      try Task.checkCancellation()
      let finishesItem = offset == selected.count - 1
      let total = Int64(upload.resource.dataSize ?? upload.expected.bytes ?? 0)
      let size = try await send(
        upload, settings: settings, total: total, onProgress: onProgress
      ) { event in
        if finishesItem {
          onBodiesSent(event)
        }
      }
      itemBytes += size
      var stored = upload.expected
      if stored.bytes == nil, size > 0 {
        stored.bytes = Int(size)
      }
      uploaded.append(stored)
    }
    return FastTransferResult(uploaded: uploaded, itemBytes: itemBytes)
  }

  private static func send(
    _ upload: LibraryUpload,
    settings: BackupSettings,
    total: Int64,
    onProgress: @escaping @Sendable (FastProgressEvent) -> Void,
    onBodySent: @escaping @Sendable (FastProgressEvent) -> Void
  ) async throws -> Int64 {
    guard let request = UploadRequest.make(settings: settings, item: upload.expected) else {
      throw FastUploadError.unreadable
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try await export(upload.resource, to: url)
    let sent = try await post(
      request: request, file: url, key: upload.expected.key, total: total, onProgress: onProgress,
      onBodySent: onBodySent)
    return max(sent, total)
  }

  private static func export(_ resource: PHAssetResource, to url: URL) async throws {
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
    let options = PHAssetResourceRequestOptions()
    options.isNetworkAccessAllowed = true
    let once = ResumeOnce()
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) {
        error in
        once.resume(error, continuation)
      }
    }
  }

  private static func post(
    request: URLRequest,
    file: URL,
    key: String,
    total: Int64,
    onProgress: @escaping @Sendable (FastProgressEvent) -> Void,
    onBodySent: @escaping @Sendable (FastProgressEvent) -> Void
  ) async throws -> Int64 {
    let bodySent = BodyOnce()
    let delegate = UploadDelegate(key: key, fallbackTotal: total) { event in
      onProgress(event)
      if event.total > 0, event.sent >= event.total {
        bodySent.fire { onBodySent(event) }
      }
    }
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 120
    configuration.timeoutIntervalForResource = 60 * 60
    configuration.waitsForConnectivity = true
    let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    return try await withTaskCancellationHandler {
      var request = request
      request.timeoutInterval = 60 * 60
      let (data, response) = try await session.upload(for: request, fromFile: file)
      try validate(response, data: data)
      session.finishTasksAndInvalidate()
      return max(delegate.sent, total)
    } onCancel: {
      session.invalidateAndCancel()
    }
  }

  private static func validate(_ response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse else {
      throw FastUploadError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      let message =
        (try? JSONDecoder().decode(FastErrorBody.self, from: data).error)
        ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
      throw FastUploadError.badStatus(http.statusCode, message)
    }
  }
}

nonisolated final class SlotGate: @unchecked Sendable {
  private let lock = NSLock()
  private var opened = false
  private var waiter: CheckedContinuation<Void, Never>?

  func open() {
    lock.lock()
    guard !opened else {
      lock.unlock()
      return
    }
    opened = true
    let waiter = waiter
    self.waiter = nil
    lock.unlock()
    waiter?.resume()
  }

  func waitUntilOpen() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      lock.lock()
      if opened {
        lock.unlock()
        continuation.resume()
        return
      }
      waiter = continuation
      lock.unlock()
    }
  }
}

nonisolated final class FastProgressRelay: @unchecked Sendable {
  private let lock = NSLock()
  private var lastPercent = -1
  private var lastDelivered = Date.distantPast
  private var pending: FastProgressEvent?
  private var flushScheduled = false

  func submit(_ event: FastProgressEvent, deliver: @escaping @Sendable (FastProgressEvent) -> Void)
  {
    let percent = FastBackupCopy.percent(event.sent, event.total)
    lock.lock()
    let due =
      percent != lastPercent || Date().timeIntervalSince(lastDelivered) >= 0.25
    if due {
      lastPercent = percent
      lastDelivered = Date()
      pending = nil
      lock.unlock()
      deliver(event)
      return
    }
    pending = event
    if flushScheduled {
      lock.unlock()
      return
    }
    flushScheduled = true
    lock.unlock()
    Task {
      try? await Task.sleep(for: .milliseconds(250))
      let latest: FastProgressEvent? = {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.flushScheduled = false
        self.lastDelivered = Date()
        if let pending = self.pending {
          self.lastPercent = FastBackupCopy.percent(pending.sent, pending.total)
        }
        let latest = self.pending
        self.pending = nil
        return latest
      }()
      if let latest {
        deliver(latest)
      }
    }
  }
}

private nonisolated final class BodyOnce: @unchecked Sendable {
  private let lock = NSLock()
  private var fired = false

  func fire(_ action: @escaping @Sendable () -> Void) {
    lock.lock()
    let shouldFire = !fired
    fired = true
    lock.unlock()
    if shouldFire {
      action()
    }
  }
}

private nonisolated final class ResumeOnce: @unchecked Sendable {
  private let lock = NSLock()
  private var resumed = false

  func resume(_ error: Error?, _ continuation: CheckedContinuation<Void, Error>) {
    lock.lock()
    defer { lock.unlock() }
    guard !resumed else { return }
    resumed = true
    if let error {
      continuation.resume(throwing: error)
    } else {
      continuation.resume()
    }
  }
}

private nonisolated final class UploadDelegate: NSObject, URLSessionTaskDelegate,
  @unchecked Sendable
{
  let key: String
  let fallbackTotal: Int64
  let onProgress: @Sendable (FastProgressEvent) -> Void
  var sent: Int64 = 0

  init(
    key: String, fallbackTotal: Int64, onProgress: @escaping @Sendable (FastProgressEvent) -> Void
  ) {
    self.key = key
    self.fallbackTotal = fallbackTotal
    self.onProgress = onProgress
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64,
    totalBytesExpectedToSend: Int64
  ) {
    sent = totalBytesSent
    let total = totalBytesExpectedToSend > 0 ? totalBytesExpectedToSend : fallbackTotal
    onProgress(FastProgressEvent(resourceKey: key, sent: totalBytesSent, total: total))
  }
}

private nonisolated struct FastErrorBody: Decodable {
  var error: String
}

nonisolated enum FastUploadError: Error, LocalizedError {
  case unreadable
  case badStatus(Int, String)
  case invalidResponse

  var errorDescription: String? {
    switch self {
    case .unreadable:
      "The photo could not be prepared for upload."
    case .badStatus(let status, let message):
      "The server returned \(status): \(message)"
    case .invalidResponse:
      "The server returned an unexpected response."
    }
  }
}
