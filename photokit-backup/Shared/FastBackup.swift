import Foundation
import Photos

struct FastProgressEvent: Sendable {
  var resourceKey: String
  var sent: Int64
  var total: Int64
}

struct FastTransferResult: Sendable {
  var uploaded: [ExpectedUpload]
  var itemBytes: Int64
}

nonisolated struct FastPreparedFile: Sendable {
  var request: URLRequest
  var file: URL
  var key: String
  var total: Int64
  var finishesItem: Bool
  var expected: ExpectedUpload
}

nonisolated struct FastPreparedUpload: Sendable {
  var files: [FastPreparedFile]

  func discard() {
    for file in files {
      try? FileManager.default.removeItem(at: file.file)
    }
  }
}

nonisolated enum FastBackupCopy {
  static func waitingLine(for items: [ListedUpload]) -> String {
    "\(mediaPhrase(items)) waiting to upload"
  }

  static func uploadingLine(for items: [ListedUpload]) -> String {
    "Uploading \(mediaPhrase(items))"
  }

  static func uploadingLine(photos: Int, videos: Int) -> String {
    "Uploading \(phrase(photos: photos, videos: videos))"
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
    return phrase(photos: items.count - videos, videos: videos)
  }

  static func phrase(photos: Int, videos: Int) -> String {
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
  /// Copies the item out of Photos. Photos only finishes one of these at a time, so callers must not hold an upload slot while this runs.
  static func prepare(
    assetId: String,
    listedID: String,
    settings: BackupSettings,
    skipKeys: Set<String>
  ) async throws -> FastPreparedUpload {
    let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
    guard let asset = assets.firstObject else {
      return FastPreparedUpload(files: [])
    }
    let selected = LibraryScanner.uploads(
      for: asset, uploadLivePhotoMovies: settings.uploadLivePhotoMovies
    ).filter { upload in
      if skipKeys.contains(upload.expected.key) { return false }
      if listedID == assetId { return true }
      return upload.expected.key == listedID
    }
    var files: [FastPreparedFile] = []
    do {
      for (offset, upload) in selected.enumerated() {
        try Task.checkCancellation()
        guard let request = UploadRequest.make(settings: settings, item: upload.expected) else {
          throw FastUploadError.unreadable
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
          try await export(upload.resource, to: url)
        } catch {
          try? FileManager.default.removeItem(at: url)
          throw error
        }
        files.append(
          FastPreparedFile(
            request: request,
            file: url,
            key: upload.expected.key,
            total: Int64(upload.resource.dataSize ?? upload.expected.bytes ?? 0),
            finishesItem: offset == selected.count - 1,
            expected: upload.expected
          ))
      }
    } catch {
      FastPreparedUpload(files: files).discard()
      throw error
    }
    return FastPreparedUpload(files: files)
  }

  static func send(
    _ prepared: FastPreparedUpload,
    onProgress: @escaping @Sendable (FastProgressEvent) -> Void,
    onBodiesSent: @escaping @Sendable (FastProgressEvent) -> Void
  ) async throws -> FastTransferResult {
    defer { prepared.discard() }
    var uploaded: [ExpectedUpload] = []
    var itemBytes: Int64 = 0
    for file in prepared.files {
      try Task.checkCancellation()
      let sent = try await post(
        request: file.request,
        file: file.file,
        key: file.key,
        total: file.total,
        onProgress: onProgress
      ) { event in
        if file.finishesItem {
          onBodiesSent(event)
        }
      }
      itemBytes += sent
      var stored = file.expected
      if stored.bytes == nil, sent > 0 {
        stored.bytes = Int(sent)
      }
      uploaded.append(stored)
    }
    return FastTransferResult(uploaded: uploaded, itemBytes: itemBytes)
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
    var request = request
    request.timeoutInterval = 60 * 60
    let (data, response, sent) = try await FastUploadSession.shared.upload(
      request: request,
      file: file,
      key: key,
      total: total,
      onProgress: onProgress,
      onBodySent: onBodySent
    )
    try validate(response, data: data)
    return max(sent, total)
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

/// One session per upload slot. A single session shares one connection and only one file keeps sending.
private nonisolated final class FastUploadSession: @unchecked Sendable {
  static let shared = FastUploadSession()

  private let lanes: [UploadLane]
  private let lock = NSLock()
  private var cursor = 0

  private init() {
    let count = max(1, BackupSettings.fastBackupConcurrencyLimit)
    lanes = (0..<count).map { _ in UploadLane() }
  }

  func upload(
    request: URLRequest,
    file: URL,
    key: String,
    total: Int64,
    onProgress: @escaping @Sendable (FastProgressEvent) -> Void,
    onBodySent: @escaping @Sendable (FastProgressEvent) -> Void
  ) async throws -> (Data, HTTPURLResponse, Int64) {
    let lane = checkout()
    defer { checkin(lane) }
    return try await lane.upload(
      request: request,
      file: file,
      key: key,
      total: total,
      onProgress: onProgress,
      onBodySent: onBodySent
    )
  }

  private func checkout() -> UploadLane {
    lock.lock()
    defer { lock.unlock() }
    if let free = lanes.first(where: { !$0.busy }) {
      free.busy = true
      return free
    }
    let lane = lanes[cursor % lanes.count]
    cursor += 1
    lane.busy = true
    return lane
  }

  private func checkin(_ lane: UploadLane) {
    lock.lock()
    lane.busy = false
    lock.unlock()
  }
}

private nonisolated final class UploadLane: @unchecked Sendable {
  let bridge = FastUploadBridge()
  let session: URLSession
  var busy = false

  init() {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 120
    configuration.timeoutIntervalForResource = 60 * 60
    configuration.waitsForConnectivity = true
    configuration.httpMaximumConnectionsPerHost = 1
    session = URLSession(configuration: configuration, delegate: bridge, delegateQueue: nil)
  }

  func upload(
    request: URLRequest,
    file: URL,
    key: String,
    total: Int64,
    onProgress: @escaping @Sendable (FastProgressEvent) -> Void,
    onBodySent: @escaping @Sendable (FastProgressEvent) -> Void
  ) async throws -> (Data, HTTPURLResponse, Int64) {
    let handler = UploadHandler(
      key: key, fallbackTotal: total, onProgress: onProgress, onBodySent: onBodySent)
    let task = session.uploadTask(with: request, fromFile: file)
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<(Data, HTTPURLResponse, Int64), Error>) in
        handler.continuation = continuation
        bridge.store(handler, for: task.taskIdentifier)
        task.resume()
      }
    } onCancel: {
      task.cancel()
    }
  }
}

private nonisolated final class FastUploadBridge: NSObject, URLSessionDataDelegate,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var handlers: [Int: UploadHandler] = [:]

  func store(_ handler: UploadHandler, for identifier: Int) {
    lock.lock()
    handlers[identifier] = handler
    lock.unlock()
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64,
    totalBytesExpectedToSend: Int64
  ) {
    let handler = handler(for: task.taskIdentifier)
    let total =
      totalBytesExpectedToSend > 0 ? totalBytesExpectedToSend : handler?.fallbackTotal ?? 0
    handler?.note(sent: totalBytesSent, total: total)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    handler(for: dataTask.taskIdentifier)?.append(data)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    let handler = removeHandler(for: task.taskIdentifier)
    guard let handler else { return }
    let response = task.response as? HTTPURLResponse
    DispatchQueue.global(qos: .utility).async {
      if let error {
        handler.fail(error)
      } else if let response {
        handler.succeed(response)
      } else {
        handler.fail(FastUploadError.invalidResponse)
      }
    }
  }

  private func handler(for identifier: Int) -> UploadHandler? {
    lock.lock()
    defer { lock.unlock() }
    return handlers[identifier]
  }

  private func removeHandler(for identifier: Int) -> UploadHandler? {
    lock.lock()
    defer { lock.unlock() }
    return handlers.removeValue(forKey: identifier)
  }
}

private nonisolated final class UploadHandler: @unchecked Sendable {
  let key: String
  let fallbackTotal: Int64
  let onProgress: @Sendable (FastProgressEvent) -> Void
  let onBodySent: @Sendable (FastProgressEvent) -> Void
  var continuation: CheckedContinuation<(Data, HTTPURLResponse, Int64), Error>?

  private let lock = NSLock()
  private let bodySent = BodyOnce()
  private var data = Data()
  private var sent: Int64 = 0
  private var resumed = false

  init(
    key: String,
    fallbackTotal: Int64,
    onProgress: @escaping @Sendable (FastProgressEvent) -> Void,
    onBodySent: @escaping @Sendable (FastProgressEvent) -> Void
  ) {
    self.key = key
    self.fallbackTotal = fallbackTotal
    self.onProgress = onProgress
    self.onBodySent = onBodySent
  }

  func note(sent: Int64, total: Int64) {
    lock.lock()
    self.sent = sent
    lock.unlock()
    let event = FastProgressEvent(resourceKey: key, sent: sent, total: total)
    onProgress(event)
    if total > 0, sent >= total {
      bodySent.fire { self.onBodySent(event) }
    }
  }

  func append(_ chunk: Data) {
    lock.lock()
    data.append(chunk)
    lock.unlock()
  }

  func succeed(_ response: HTTPURLResponse) {
    finish(.success((snapshotData(), response, snapshotSent())))
  }

  func fail(_ error: Error) {
    finish(.failure(error))
  }

  private func snapshotData() -> Data {
    lock.lock()
    defer { lock.unlock() }
    return data
  }

  private func snapshotSent() -> Int64 {
    lock.lock()
    defer { lock.unlock() }
    return sent
  }

  private func finish(_ result: Result<(Data, HTTPURLResponse, Int64), Error>) {
    lock.lock()
    guard !resumed else {
      lock.unlock()
      return
    }
    resumed = true
    let continuation = continuation
    self.continuation = nil
    lock.unlock()
    switch result {
    case .success(let value):
      continuation?.resume(returning: value)
    case .failure(let error):
      continuation?.resume(throwing: error)
    }
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
