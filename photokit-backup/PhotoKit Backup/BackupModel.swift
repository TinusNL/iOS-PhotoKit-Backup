import Foundation
import Network
import Observation
import Photos
import UIKit
@preconcurrency import UserNotifications

@MainActor
@Observable
final class FastItemProgress {
  var sent: Int64
  var total: Int64

  init(sent: Int64, total: Int64) {
    self.sent = sent
    self.total = total
  }

  var fraction: Double {
    guard total > 0 else { return 0 }
    return min(1, Double(sent) / Double(total))
  }

  var percent: Int {
    FastBackupCopy.percent(sent, total)
  }
}

@MainActor
@Observable
final class BackupModel {
  var serverField = ""
  var apiKeyField = ""
  var accountName = ""
  var recentRows: [ListedUpload] = []
  var recentTotal = 0
  var recentLoaded: Int { recentFiles.count }
  var isLoadingMoreRecent = false
  var pending: [ListedUpload] = []
  var pendingShown = 0
  var browsePendingShown = browsePageSize
  var browseRecentShown = browsePageSize
  var isLoadingPending = false
  var hasMorePending: Bool { pendingIndex < pendingAssetCount }
  var pendingIsComplete: Bool { didCheckPending && !hasMorePending }
  var uploadLivePhotoMovies = true
  var requireWifi = BackupSettings.requireWifi
  var isOnWifi = true
  var fastBackupConcurrency = BackupSettings.fastBackupConcurrency
  var notificationsEnabled = BackupSettings.notificationsEnabled
  var notificationAuthorization: UNAuthorizationStatus = .notDetermined
  var didCompleteOnboarding = BackupSettings.didCompleteOnboarding
  var isSignedIn = false
  var isWorking = false
  var serverReachable: Bool?
  var statusMessage: String?
  var photoStatus: PHAuthorizationStatus = .notDetermined
  var isPreview = false
  var selectedTab: BackupTab = .backup
  var fastBackupPhase: FastBackupPhase = .idle
  var fastBackupCompleted = 0
  var fastBackupTotal = 0
  var fastBackupSent: Int64 = 0
  var fastBackupTotalBytes: Int64 = 0
  var fastItemProgress: [String: FastItemProgress] = [:]

  var showsFastBackup: Bool {
    photoStatus == .authorized && (fastBackupPhase != .idle || !pending.isEmpty)
  }

  var fastBackupFraction: Double {
    if fastBytesCoverAll, fastBackupTotalBytes > 0 {
      return min(1, Double(fastBackupSent) / Double(fastBackupTotalBytes))
    }
    guard fastBackupTotal > 0 else { return 0 }
    let partial = fastItemProgress.values.reduce(0.0) { $0 + $1.fraction }
    return min(1, (Double(fastBackupCompleted) + partial) / Double(fastBackupTotal))
  }

  /// Byte total for the progress label. Stays hidden until every file in the backup is included.
  var fastBackupShownTotalBytes: Int64 {
    fastBytesCoverAll ? fastBackupTotalBytes : 0
  }

  var fastBackupNeedsWifi: Bool {
    fastBackupPhase == .idle && requireWifi && !isOnWifi
  }

  var fastBackupSubtitle: String {
    if fastBackupPhase == .running {
      return FastBackupCopy.uploadingLine(
        photos: fastQueuedPhotoCount, videos: fastQueuedVideoCount)
    }
    return FastBackupCopy.waitingLine(for: pending)
  }

  static func preview(
    accountName: String = "tinus",
    photoStatus: PHAuthorizationStatus = .authorized,
    uploadLivePhotoMovies: Bool = true
  ) -> BackupModel {
    let model = BackupModel()
    model.isPreview = true
    model.isSignedIn = true
    model.accountName = accountName
    model.serverField = "http://192.168.1.20:8080"
    model.apiKeyField = "preview-key"
    model.photoStatus = photoStatus
    model.uploadLivePhotoMovies = uploadLivePhotoMovies
    model.notificationsEnabled = true
    model.notificationAuthorization = .authorized
    model.didCompleteOnboarding = true
    model.serverReachable = true
    let uploadedLive = [
      ExpectedUpload(
        assetId: "preview-uploaded", resourceType: "photo", filename: "IMG_2456.HEIC",
        relativePath: "2026/10/IMG_2456.HEIC", isoTimestamp: "2026-10-20T12:00:00+02:00",
        bytes: 2_481_332),
      ExpectedUpload(
        assetId: "preview-uploaded", resourceType: "pairedVideo", filename: "IMG_2456.MOV",
        relativePath: "2026/10/IMG_2456.MOV", isoTimestamp: "2026-10-20T12:00:00+02:00",
        bytes: 8_912_440),
    ]
    let waiting = [
      ExpectedUpload(
        assetId: "preview-live", resourceType: "photo", filename: "IMG_3102.HEIC",
        relativePath: "2026/10/IMG_3102.HEIC", isoTimestamp: "2026-10-20T15:02:00+02:00",
        bytes: 1_200_000),
      ExpectedUpload(
        assetId: "preview-live", resourceType: "pairedVideo", filename: "IMG_3102.MOV",
        relativePath: "2026/10/IMG_3102.MOV", isoTimestamp: "2026-10-20T15:02:00+02:00",
        bytes: 4_500_000),
      ExpectedUpload(
        assetId: "preview-video", resourceType: "video", filename: "IMG_3104.MP4",
        relativePath: "2026/10/IMG_3104.MP4", isoTimestamp: "2026-10-18T09:41:00+02:00",
        bytes: 18_000_000),
    ]
    model.expectedUploads = uploadedLive + waiting
    model.recentFiles = [
      RemoteFile(
        filename: "IMG_2456.HEIC", relativePath: "2026/10/IMG_2456.HEIC", bytes: 2_481_332,
        contentType: "image/heic", createdAt: "2026-10-01T00:00:00.000Z",
        uploadedAt: "2026-10-20T12:04:00.000Z"),
      RemoteFile(
        filename: "IMG_2456.MOV", relativePath: "2026/10/IMG_2456.MOV", bytes: 8_912_440,
        contentType: "video/quicktime", createdAt: "2026-10-01T00:00:00.000Z",
        uploadedAt: "2026-10-20T12:05:00.000Z"),
      RemoteFile(
        filename: "IMG_2450.JPG", relativePath: "2019/03/IMG_2450.JPG", bytes: 3_102_884,
        contentType: "image/jpeg", createdAt: "2019-03-01T00:00:00.000Z",
        uploadedAt: "2026-10-19T18:12:00.000Z"),
    ]
    model.recentRows = UploadGroups.recent(files: model.recentFiles, library: model.expectedUploads)
    model.recentTotal = model.recentFiles.count
    model.pending = UploadGroups.pending(
      expected: waiting,
      uploaded: ["preview-live": ["photo"]]
    )
    model.pendingShown = model.pending.count
    model.didCheckPending = true
    return model
  }

  static func previewInProgress() -> BackupModel {
    let model = preview()
    model.fastBackupPhase = .running
    model.fastQueue = model.pending
    model.recountQueuedMedia()
    model.fastBackupCompleted = 0
    model.fastBackupTotal = model.pending.count
    model.fastBackupTotalBytes = model.pending.reduce(0) { $0 + Int64($1.bytes ?? 0) }
    for (index, item) in model.pending.enumerated() {
      let total = Int64(item.bytes ?? 1)
      let sent = index == 0 ? total * 3 / 5 : total / 5
      model.fastItemProgress[item.id] = FastItemProgress(sent: sent, total: total)
    }
    model.fastBackupSent = model.fastItemProgress.values.reduce(0) { $0 + $1.sent }
    model.fastBytesCoverAll = true
    return model
  }

  func restore() {
    guard !isPreview else { return }
    photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    uploadLivePhotoMovies = BackupSettings.uploadLivePhotoMovies
    requireWifi = BackupSettings.requireWifi
    fastBackupConcurrency = BackupSettings.fastBackupConcurrency
    startWifiMonitor()
    notificationsEnabled = BackupSettings.notificationsEnabled
    didCompleteOnboarding = BackupSettings.didCompleteOnboarding
    if let settings = BackupSettings.load() {
      serverField = settings.serverURL.absoluteString
      apiKeyField = settings.apiKey
      isSignedIn = true
    } else {
      isSignedIn = false
    }
  }

  func connect() async {
    guard let serverURL = ServerAddress.normalize(serverField) else {
      statusMessage = "Enter a server address, such as 192.168.1.20:8080."
      return
    }
    let apiKey = apiKeyField.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !apiKey.isEmpty else {
      statusMessage = "Enter an API key."
      return
    }

    isWorking = true
    statusMessage = nil
    defer { isWorking = false }

    do {
      let name = try await BackupClient(baseURL: serverURL, apiKey: apiKey).sessionName()
      let settings = BackupSettings(
        serverURL: serverURL,
        apiKey: apiKey,
        uploadLivePhotoMovies: uploadLivePhotoMovies,
        requireWifi: requireWifi
      )
      try settings.save()
      accountName = name
      serverField = serverURL.absoluteString
      serverReachable = true
      BackupSettings.setDidCompleteOnboarding(true)
      didCompleteOnboarding = true
      isSignedIn = true
      await enableUploadsIfAuthorized()
      await refresh()
    } catch {
      serverReachable = false
      statusMessage = error.localizedDescription
    }
  }

  /// Starts a library load once. Later appearances reuse it, including while it is still running.
  func loadIfNeeded() {
    guard !isPreview, libraryTask == nil else { return }
    libraryGeneration += 1
    let generation = libraryGeneration
    libraryTask = Task.detached { @MainActor in
      await self.refreshLibrary(generation: generation)
    }
  }

  func refresh() async {
    guard !isPreview else { return }
    stopFastBackup()
    libraryTask?.cancel()
    libraryGeneration += 1
    let generation = libraryGeneration
    let task = Task.detached { @MainActor in
      await self.refreshLibrary(generation: generation)
    }
    libraryTask = task
    await task.value
  }

  private func refreshLibrary(generation: Int) async {
    guard generation == libraryGeneration else { return }
    guard let settings = BackupSettings.load() else {
      isSignedIn = false
      return
    }
    isWorking = true
    defer { isWorking = false }
    photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    await enableUploadsIfAuthorized()

    do {
      let client = BackupClient(baseURL: settings.serverURL, apiKey: settings.apiKey)
      accountName = try await client.sessionName()
      guard generation == libraryGeneration else { return }
      serverReachable = true
      let recentScan = recentGeneration + 1
      recentGeneration = recentScan
      let page = try await client.recent(limit: Self.recentPageSize)
      guard generation == libraryGeneration, recentScan == recentGeneration else { return }
      replaceRecent(page.items)
      recentTotal = page.total
      await Task.yield()
      guard generation == libraryGeneration else { return }
      pendingGeneration += 1
      pending = []
      pendingShown = 0
      browsePendingShown = Self.browsePageSize
      browseRecentShown = Self.browsePageSize
      pendingIndex = 0
      pendingAssetCount = 0
      didCheckPending = false
      expectedUploads = []
      statusMessage = nil
      isWorking = false
      let pendingScan = pendingGeneration
      isLoadingPending = true
      await loadPendingPage(limit: Self.pendingPageSize, priority: .userInitiated)
      guard generation == libraryGeneration, pendingScan == pendingGeneration else { return }
      isLoadingPending = false
      await countRemainingPending()
    } catch {
      serverReachable = false
      statusMessage = error.localizedDescription
    }
  }

  func loadMoreRecent() async {
    await loadMoreRecent(limit: Self.recentPageSize)
  }

  func loadMoreRecent(limit: Int) async {
    guard !isPreview, !isWorking, !isLoadingMoreRecent, recentFiles.count < recentTotal else {
      return
    }
    guard let settings = BackupSettings.load() else { return }
    isLoadingMoreRecent = true
    let generation = recentGeneration
    let offset = recentFiles.count
    defer { isLoadingMoreRecent = false }
    do {
      let page = try await BackupClient(baseURL: settings.serverURL, apiKey: settings.apiKey)
        .recent(
          limit: limit,
          offset: offset
        )
      guard generation == recentGeneration else { return }
      recentTotal = page.total
      let known = Set(recentFiles.map(\.id))
      recentFiles.append(contentsOf: page.items.filter { !known.contains($0.id) })
      recentRows = UploadGroups.recent(files: recentFiles, library: expectedUploads)
    } catch {
      serverReachable = false
      statusMessage = error.localizedDescription
    }
  }

  func prepareFileBrowse(_ list: BackupFileList) async {
    switch list {
    case .pending:
      browsePendingShown = max(browsePendingShown, Self.browsePageSize)
    case .recent:
      browseRecentShown = max(browseRecentShown, Self.browsePageSize)
      await loadRecentRows(until: browseRecentShown)
    }
  }

  func loadNextFilePage(_ list: BackupFileList) async {
    switch list {
    case .pending:
      guard pending.count > browsePendingShown else { return }
      browsePendingShown = min(pending.count, browsePendingShown + Self.browsePageSize)
    case .recent:
      let target = browseRecentShown + Self.browsePageSize
      if recentRows.count <= browseRecentShown {
        await loadRecentRows(until: target)
      }
      browseRecentShown = min(target, max(recentRows.count, browseRecentShown))
    }
  }

  func notifyFastBackupNeedsAppOpen() {
    guard !isPreview, fastBackupPhase == .running, notificationsEnabled else { return }
    guard fastBackupStayOpenNoticeID == nil else { return }
    let identifier = "\(Self.fastBackupStayOpenNotice)-\(UUID().uuidString)"
    fastBackupStayOpenNoticeID = identifier
    let content = UNMutableNotificationContent()
    content.title = "PhotoKit Backup"
    content.body = "Fast backup paused. Keep the app open to continue uploading."
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let request = UNNotificationRequest(
      identifier: identifier, content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request) { _ in
      Task { @MainActor in
        guard self.fastBackupStayOpenNoticeID != identifier else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
      }
    }
  }

  func clearFastBackupNeedsAppOpenNotice() {
    guard !isPreview else { return }
    let center = UNUserNotificationCenter.current()
    var identifiers = [Self.fastBackupStayOpenNotice]
    if let identifier = fastBackupStayOpenNoticeID {
      identifiers.append(identifier)
    }
    fastBackupStayOpenNoticeID = nil
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
    center.removeDeliveredNotifications(withIdentifiers: identifiers)
  }

  func setUploadLivePhotoMovies(_ enabled: Bool) {
    uploadLivePhotoMovies = enabled
    guard !isPreview else { return }
    BackupSettings.setUploadLivePhotoMovies(enabled)
  }

  func setRequireWifi(_ enabled: Bool) {
    requireWifi = enabled
    guard !isPreview else { return }
    BackupSettings.setRequireWifi(enabled)
    applyBackgroundUploadNetworkPolicy()
    if enabled, !isOnWifi {
      stopFastBackup()
    }
  }

  func showSettings() {
    selectedTab = .settings
  }

  func setFastBackupConcurrency(_ count: Int) {
    let clamped = min(max(count, 1), BackupSettings.fastBackupConcurrencyLimit)
    fastBackupConcurrency = clamped
    guard !isPreview else { return }
    BackupSettings.setFastBackupConcurrency(clamped)
  }

  func refreshNotificationAuthorization() async {
    guard !isPreview else { return }
    let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    notificationAuthorization = status
    if status == .denied {
      notificationsEnabled = false
      BackupSettings.setNotificationsEnabled(false)
    }
  }

  func setNotificationsEnabled(_ enabled: Bool) async {
    guard !isPreview else {
      notificationsEnabled = enabled
      return
    }
    if !enabled {
      notificationsEnabled = false
      BackupSettings.setNotificationsEnabled(false)
      return
    }
    let center = UNUserNotificationCenter.current()
    var status = await center.notificationSettings().authorizationStatus
    if status == .notDetermined {
      _ = try? await center.requestAuthorization(options: [.alert])
      status = await center.notificationSettings().authorizationStatus
    }
    notificationAuthorization = status
    let allowed = status == .authorized || status == .provisional || status == .ephemeral
    notificationsEnabled = allowed
    BackupSettings.setNotificationsEnabled(allowed)
  }

  func requestNotifications() async {
    guard !isPreview else { return }
    isWorking = true
    defer { isWorking = false }
    let center = UNUserNotificationCenter.current()
    _ = try? await center.requestAuthorization(options: [.alert])
    let status = await center.notificationSettings().authorizationStatus
    notificationAuthorization = status
    let allowed = status == .authorized || status == .provisional || status == .ephemeral
    notificationsEnabled = allowed
    BackupSettings.setNotificationsEnabled(allowed)
  }

  func signOut() {
    guard !isPreview else {
      isSignedIn = false
      accountName = ""
      recentFiles = []
      recentRows = []
      recentTotal = 0
      pending = []
      pendingShown = 0
      isLoadingPending = false
      pendingIndex = 0
      pendingAssetCount = 0
      didCheckPending = false
      serverReachable = nil
      return
    }
    let photoLibrary = PHPhotoLibrary.shared()
    if photoLibrary.uploadJobExtensionEnabled {
      try? photoLibrary.disableUploadJobExtension()
    }
    libraryTask?.cancel()
    libraryTask = nil
    libraryGeneration += 1
    discardFastBackup()
    BackupSettings.signOut()
    apiKeyField = ""
    accountName = ""
    recentGeneration += 1
    pendingGeneration += 1
    recentFiles = []
    recentRows = []
    recentTotal = 0
    expectedUploads = []
    pending = []
    pendingShown = 0
    isLoadingPending = false
    pendingIndex = 0
    pendingAssetCount = 0
    didCheckPending = false
    isSignedIn = false
    serverReachable = nil
    statusMessage = nil
  }

  static let browsePageSize = 50
  static let homePendingPreview = 5
  static let homeRecentPreview = 5
  nonisolated static let fastBackupStayOpenNotice = "photokit-backup-stay-open"
  private var fastBackupStayOpenNoticeID: String?
  private static let pendingPageSize = 5
  private static let recentPageSize = 10
  private let wifiMonitor = WifiMonitor()
  private var didStartWifiMonitor = false
  private var libraryTask: Task<Void, Never>?
  private var libraryGeneration = 0
  private var fastBackupTask: Task<Void, Never>?
  private var fastBytesCoverAll = false
  private var fastQueuedBytes: [String: Int64] = [:]
  private var fastQueue: [ListedUpload] = []
  private var fastQueuedPhotoCount = 0
  private var fastQueuedVideoCount = 0
  private var fastInFlight: Set<String> = []
  private var fastStarted: Set<String> = []
  private var fastOutstanding = 0
  private var fastFinishedKeys: Set<String> = []
  private var fastFinishedRowIDs: Set<String> = []
  private var fastRetiredIDs: Set<String> = []
  private var fastAwaitingConfirm: [ListedUpload] = []
  private var fastCommittedBytes: Int64 = 0
  private var fastResourceSent: [String: Int64] = [:]
  private var fastResourceTotal: [String: Int64] = [:]
  private var fastResourceOwner: [String: String] = [:]
  private var recentFiles: [RemoteFile] = []
  private var expectedUploads: [ExpectedUpload] = []
  private var recentGeneration = 0
  private var pendingGeneration = 0
  private var pendingIndex = 0
  private var pendingAssetCount = 0
  private var didCheckPending = false

  private func countRemainingPending() async {
    guard hasMorePending else { return }
    let generation = pendingGeneration
    isLoadingPending = true
    defer {
      if generation == pendingGeneration {
        isLoadingPending = false
      }
    }
    guard let settings = BackupSettings.load() else { return }
    let start = pendingIndex
    let movies = settings.uploadLivePhotoMovies
    let pages = AsyncStream<LibraryPage> { continuation in
      Task.detached(priority: .utility) {
        LibraryScanner.forEachPage(
          start: start, batchSize: 200, uploadLivePhotoMovies: movies
        ) { page in
          continuation.yield(page)
        }
        continuation.finish()
      }
    }
    for await page in pages {
      guard generation == pendingGeneration else { return }
      let loaded = await applyPending(page, generation: generation)
      guard loaded else { return }
    }
  }

  @discardableResult
  private func loadPendingPage(limit: Int, priority: TaskPriority = .utility) async -> Bool {
    let generation = pendingGeneration
    guard let settings = BackupSettings.load() else { return false }
    let start = pendingIndex
    let movies = settings.uploadLivePhotoMovies
    let page = await Task.detached(priority: priority) {
      LibraryScanner.page(start: start, limit: limit, uploadLivePhotoMovies: movies)
    }.value
    guard generation == pendingGeneration else { return false }
    return await applyPending(page, generation: generation)
  }

  private func applyPending(_ page: LibraryPage, generation: Int) async -> Bool {
    guard generation == pendingGeneration else { return false }
    guard let settings = BackupSettings.load() else { return false }
    pendingIndex = page.nextIndex
    pendingAssetCount = page.total
    let client = BackupClient(baseURL: settings.serverURL, apiKey: settings.apiKey)
    let chunkSize = 200
    var index = 0
    while index < page.uploads.count {
      guard generation == pendingGeneration else { return false }
      let end = min(index + chunkSize, page.uploads.count)
      let slice = Array(page.uploads[index..<end])
      do {
        let stored = try await client.lookup(slice)
        guard generation == pendingGeneration else { return false }
        expectedUploads.append(contentsOf: slice)
        var storedWithLocal = stored
        for key in fastFinishedKeys {
          let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
          guard parts.count == 2 else { continue }
          storedWithLocal[parts[0], default: []].insert(parts[1])
        }
        let rows = UploadGroups.pending(expected: slice, uploaded: storedWithLocal).filter {
          !fastFinishedRowIDs.contains($0.id) && !fastRetiredIDs.contains($0.id)
        }
        pending.append(contentsOf: rows)
        if pendingShown == 0, !pending.isEmpty {
          pendingShown = min(Self.pendingPageSize, pending.count)
        }
      } catch {
        serverReachable = false
        statusMessage = error.localizedDescription
        return false
      }
      index = end
      await Task.yield()
    }
    recentRows = UploadGroups.recent(files: recentFiles, library: expectedUploads)
    didCheckPending = !hasMorePending
    return true
  }

  private func loadRecentRows(until target: Int) async {
    while recentRows.count < target, recentFiles.count < recentTotal {
      let before = recentFiles.count
      await loadMoreRecent(limit: Self.browsePageSize)
      if recentFiles.count == before { return }
    }
  }

  private func replaceRecent(_ files: [RemoteFile]) {
    recentFiles = files
    recentRows = UploadGroups.recent(files: files, library: expectedUploads)
  }

  private func enableUploadsIfAuthorized() async {
    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    photoStatus = status
    guard status == .authorized else { return }
    let photoLibrary = PHPhotoLibrary.shared()
    let options = uploadJobOptions()
    do {
      if photoLibrary.uploadJobExtensionEnabled {
        try photoLibrary.setUploadJobExtensionOptions(options)
      } else {
        try photoLibrary.enableUploadJobExtension(with: options)
      }
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  private func applyBackgroundUploadNetworkPolicy() {
    guard !isPreview else { return }
    guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else { return }
    let photoLibrary = PHPhotoLibrary.shared()
    guard photoLibrary.uploadJobExtensionEnabled else { return }
    do {
      try photoLibrary.setUploadJobExtensionOptions(uploadJobOptions())
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  private func uploadJobOptions() -> PHAssetResourceUploadJobOptions {
    let options = PHAssetResourceUploadJobOptions()
    options.preventsExpensiveNetworkAccess = requireWifi
    return options
  }

  private func startWifiMonitor() {
    guard !isPreview, !didStartWifiMonitor else { return }
    didStartWifiMonitor = true
    wifiMonitor.start { [weak self] onWifi in
      Task { @MainActor [weak self] in
        self?.noteWifiReachability(onWifi)
      }
    }
  }

  private func noteWifiReachability(_ onWifi: Bool) {
    isOnWifi = onWifi
    if requireWifi, !onWifi {
      stopFastBackup()
    }
  }

  func requestPhotoAccess() async {
    let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    photoStatus = status
    if status == .authorized {
      await refresh()
    } else {
      statusMessage = "Full photo library access is required before background upload can start."
    }
  }

  func startFastBackup() {
    guard !isPreview, photoStatus == .authorized, fastBackupPhase != .running else { return }
    if let onWifi = wifiMonitor.knownWifi() {
      isOnWifi = onWifi
    }
    guard !fastBackupNeedsWifi else { return }
    guard !pending.isEmpty else { return }
    if fastBackupPhase == .idle {
      fastQueue = pending
      recountQueuedMedia()
      fastFinishedKeys = []
      fastFinishedRowIDs = []
      fastRetiredIDs = []
      fastAwaitingConfirm = []
      fastInFlight = []
      fastStarted = []
      fastOutstanding = 0
      fastItemProgress = [:]
      fastResourceSent = [:]
      fastResourceTotal = [:]
      fastResourceOwner = [:]
      fastCommittedBytes = 0
      fastBackupSent = 0
      fastBackupCompleted = 0
      fastBackupTotal = pending.count
      fastBackupTotalBytes = pending.reduce(0) { $0 + Int64($1.bytes ?? 0) }
      fastBytesCoverAll = pending.allSatisfy { ($0.bytes ?? 0) > 0 }
      if fastBytesCoverAll {
        for item in pending {
          fastQueuedBytes[item.id] = Int64(item.bytes ?? 0)
        }
      }
    }
    fastBackupPhase = .running
    statusMessage = nil
    updateScreenAwake()
    fastBackupTask = Task { await runFastBackup() }
  }

  func updateScreenAwake() {
    guard !isPreview else { return }
    UIApplication.shared.isIdleTimerDisabled = fastBackupPhase == .running
  }

  func stopFastBackup() {
    guard fastBackupPhase == .running else { return }
    fastBackupTask?.cancel()
    restoreUnconfirmedRows()
    finishFastBackup()
  }

  private func runFastBackup() async {
    await withTaskGroup(of: Void.self) { group in
      var launched = 0
      while fastBackupPhase == .running, !Task.isCancelled {
        let wanted = max(1, fastBackupConcurrency)
        while launched < wanted {
          launched += 1
          group.addTask { @MainActor in
            await self.fastBackupWorker()
          }
        }
        if !isLoadingPending, fastOutstanding == 0, fastQueue.isEmpty {
          finishFastBackup()
          break
        }
        try? await Task.sleep(for: .milliseconds(200))
      }
      group.cancelAll()
    }
    fastInFlight.removeAll()
  }

  /// Keeps uploading the next file as soon as one has sent its bytes, instead of waiting for the whole group.
  private func fastBackupWorker() async {
    while fastBackupPhase == .running, !Task.isCancelled {
      let sendingLimit = max(1, fastBackupConcurrency)
      while fastInFlight.count >= sendingLimit || fastOutstanding >= sendingLimit {
        if fastBackupPhase != .running || Task.isCancelled { return }
        try? await Task.sleep(for: .milliseconds(100))
      }
      guard let item = claimNextFastItem() else {
        try? await Task.sleep(for: .milliseconds(200))
        continue
      }
      await uploadUntilSlotFrees(item)
    }
  }

  private func claimNextFastItem() -> ListedUpload? {
    adoptNewPending()
    guard fastBackupPhase == .running else { return nil }
    guard let item = fastQueue.first(where: { !fastStarted.contains($0.id) }) else { return nil }
    fastStarted.insert(item.id)
    fastInFlight.insert(item.id)
    fastOutstanding += 1
    return item
  }

  private func uploadUntilSlotFrees(_ item: ListedUpload) async {
    defer { fastInFlight.remove(item.id) }
    guard let settings = BackupSettings.load() else {
      fastStarted.remove(item.id)
      fastOutstanding = max(0, fastOutstanding - 1)
      return
    }
    let assetId = item.assetId
    let itemID = item.id
    let skipKeys = fastFinishedKeys
    let relay = FastProgressRelay()
    let gate = SlotGate()
    let work = Task.detached(priority: .utility) { () throws -> FastTransferResult in
      defer { gate.open() }
      return try await FastUploader.transfer(
        assetId: assetId,
        listedID: itemID,
        settings: settings,
        skipKeys: skipKeys,
        onProgress: { event in
          relay.submit(event) { latest in
            Task { @MainActor in
              self.noteFastResourceProgress(
                itemID: itemID, key: latest.resourceKey, sent: latest.sent, total: latest.total)
            }
          }
        },
        onBodiesSent: { event in
          gate.open()
          Task { @MainActor in
            self.noteFastResourceProgress(
              itemID: itemID, key: event.resourceKey, sent: event.sent, total: event.total)
            self.retireSentItem(item)
          }
        }
      )
    }
    await withTaskCancellationHandler {
      await gate.waitUntilOpen()
    } onCancel: {
      work.cancel()
      gate.open()
    }
    Task { @MainActor in
      await self.finishUploadTask(item, work)
    }
  }

  private func finishUploadTask(_ item: ListedUpload, _ work: Task<FastTransferResult, Error>) async
  {
    defer {
      fastStarted.remove(item.id)
      fastOutstanding = max(0, fastOutstanding - 1)
    }
    do {
      let result = try await withTaskCancellationHandler {
        try await work.value
      } onCancel: {
        work.cancel()
      }
      guard fastBackupPhase == .running, !Task.isCancelled else { return }
      if result.uploaded.isEmpty {
        dropQueued(item)
        return
      }
      if result.itemBytes > 0 {
        fastQueuedBytes[item.id] = result.itemBytes
      }
      for upload in result.uploaded {
        fastFinishedKeys.insert(upload.key)
        rememberUploaded(upload, bytes: Int64(upload.bytes ?? 0))
      }
      if fastAwaitingConfirm.contains(where: { $0.id == item.id }) {
        fastAwaitingConfirm.removeAll { $0.id == item.id }
        fastRetiredIDs.remove(item.id)
        fastFinishedRowIDs.insert(item.id)
      } else {
        finishQueued(item)
      }
    } catch is CancellationError {
      return
    } catch let error as URLError where error.code == .cancelled {
      return
    } catch {
      guard fastBackupPhase == .running else { return }
      serverReachable = false
      statusMessage = error.localizedDescription
      stopFastBackup()
    }
  }

  private func noteFastResourceProgress(itemID: String, key: String, sent: Int64, total: Int64) {
    guard fastBackupPhase == .running else { return }
    guard !fastRetiredIDs.contains(itemID), !fastFinishedRowIDs.contains(itemID) else { return }
    let knownTotal = fastResourceTotal[key] ?? 0
    fastResourceOwner[key] = itemID
    fastResourceSent[key] = sent
    fastResourceTotal[key] = max(knownTotal, total)
    let keys = fastResourceOwner.filter { $0.value == itemID }.map(\.key)
    let itemSent = keys.reduce(Int64(0)) { $0 + (fastResourceSent[$1] ?? 0) }
    let itemTotal = keys.reduce(Int64(0)) { $0 + (fastResourceTotal[$1] ?? 0) }
    if let progress = fastItemProgress[itemID] {
      progress.sent = itemSent
      progress.total = itemTotal
    } else {
      fastItemProgress[itemID] = FastItemProgress(sent: itemSent, total: itemTotal)
    }
    fastBackupSent = fastCommittedBytes + fastResourceSent.values.reduce(0, +)
  }

  private func adoptNewPending() {
    guard fastBackupPhase == .running else { return }
    let known = Set(fastQueue.map(\.id)).union(fastFinishedRowIDs).union(fastRetiredIDs)
    for item in pending where !known.contains(item.id) {
      fastQueue.append(item)
      addQueuedMedia(item)
      fastBackupTotal += 1
      if let bytes = item.bytes, bytes > 0 {
        fastQueuedBytes[item.id] = Int64(bytes)
      }
    }
    refreshFastByteTotalIfReady()
  }

  /// Drops a row once its bytes are sent. The server response is recorded separately.
  private func retireSentItem(_ item: ListedUpload) {
    guard fastBackupPhase == .running else { return }
    guard !fastFinishedRowIDs.contains(item.id), !fastRetiredIDs.contains(item.id) else { return }
    accountFinished(item)
    fastRetiredIDs.insert(item.id)
    fastAwaitingConfirm.append(item)
    dropQueued(item)
  }

  private func finishQueued(_ item: ListedUpload) {
    accountFinished(item)
    fastFinishedRowIDs.insert(item.id)
    dropQueued(item)
  }

  private func accountFinished(_ item: ListedUpload) {
    let keys = fastResourceOwner.filter { $0.value == item.id }.map(\.key)
    let itemTotal = keys.reduce(Int64(0)) { $0 + (fastResourceTotal[$1] ?? 0) }
    fastCommittedBytes += itemTotal
    for key in keys {
      fastResourceSent[key] = nil
      fastResourceTotal[key] = nil
      fastResourceOwner[key] = nil
    }
    fastBackupSent = fastCommittedBytes + fastResourceSent.values.reduce(0, +)
    fastItemProgress[item.id] = nil
    fastBackupCompleted += 1
    if fastQueuedBytes[item.id] == nil {
      fastQueuedBytes[item.id] = itemTotal > 0 ? itemTotal : Int64(item.bytes ?? 0)
    }
    refreshFastByteTotalIfReady()
  }

  private func restoreUnconfirmedRows() {
    let waiting = fastAwaitingConfirm
    fastAwaitingConfirm = []
    fastRetiredIDs = []
    let missing = waiting.filter { item in !pending.contains { $0.id == item.id } }
    guard !missing.isEmpty else { return }
    pending.insert(contentsOf: missing, at: 0)
  }

  private func dropQueued(_ item: ListedUpload) {
    if let index = fastQueue.firstIndex(where: { $0.id == item.id }) {
      fastQueue.remove(at: index)
      removeQueuedMedia(item)
    }
    if let index = pending.firstIndex(where: { $0.id == item.id }) {
      pending.remove(at: index)
    }
  }

  private func recountQueuedMedia() {
    fastQueuedPhotoCount = 0
    fastQueuedVideoCount = 0
    for item in fastQueue {
      addQueuedMedia(item)
    }
  }

  private func addQueuedMedia(_ item: ListedUpload) {
    if FastBackupCopy.isVideo(item) {
      fastQueuedVideoCount += 1
    } else {
      fastQueuedPhotoCount += 1
    }
  }

  private func removeQueuedMedia(_ item: ListedUpload) {
    if FastBackupCopy.isVideo(item) {
      fastQueuedVideoCount = max(0, fastQueuedVideoCount - 1)
    } else {
      fastQueuedPhotoCount = max(0, fastQueuedPhotoCount - 1)
    }
  }

  private func rememberUploaded(_ item: ExpectedUpload, bytes: Int64) {
    let file = RemoteFile(
      filename: item.filename,
      relativePath: item.relativePath,
      bytes: max(Int(bytes), item.bytes ?? 0),
      contentType: UploadNaming.contentType(for: item.filename),
      createdAt: item.isoTimestamp,
      uploadedAt: ISO8601DateFormatter().string(from: Date())
    )
    let isNew = !recentFiles.contains { $0.relativePath == file.relativePath }
    recentFiles.removeAll { $0.relativePath == file.relativePath }
    recentFiles.insert(file, at: 0)
    if isNew {
      recentTotal += 1
    }
    recentRows = UploadGroups.insertRecent(file: file, assetId: item.assetId, into: recentRows)
  }

  private func refreshFastByteTotalIfReady() {
    guard fastBytesCoverAll else { return }
    fastBackupTotalBytes = fastQueuedBytes.values.reduce(0, +)
  }

  private func finishFastBackup() {
    fastBackupPhase = .idle
    fastBackupTask = nil
    fastBytesCoverAll = false
    fastQueuedBytes = [:]
    fastQueue = []
    fastQueuedPhotoCount = 0
    fastQueuedVideoCount = 0
    fastInFlight = []
    fastStarted = []
    fastOutstanding = 0
    fastRetiredIDs = []
    fastAwaitingConfirm = []
    fastItemProgress = [:]
    fastResourceSent = [:]
    fastResourceTotal = [:]
    fastResourceOwner = [:]
    fastCommittedBytes = 0
    fastBackupSent = 0
    fastBackupTotal = 0
    fastBackupCompleted = 0
    fastBackupTotalBytes = 0
    updateScreenAwake()
  }

  private func discardFastBackup() {
    stopFastBackup()
    fastFinishedKeys = []
    fastFinishedRowIDs = []
    fastRetiredIDs = []
    fastAwaitingConfirm = []
  }
}

private final class WifiMonitor: @unchecked Sendable {
  private let monitor = NWPathMonitor()
  private let lock = NSLock()
  private var latest: Bool?

  func start(onChange: @escaping @Sendable (Bool) -> Void) {
    monitor.pathUpdateHandler = { [weak self] path in
      let onWifi =
        path.status == .satisfied
        && (path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet))
      self?.store(onWifi)
      onChange(onWifi)
    }
    monitor.start(queue: DispatchQueue(label: "com.tinusnl.photokit-backup.network"))
  }

  func knownWifi() -> Bool? {
    lock.lock()
    defer { lock.unlock() }
    return latest
  }

  private func store(_ onWifi: Bool) {
    lock.lock()
    latest = onWifi
    lock.unlock()
  }
}
