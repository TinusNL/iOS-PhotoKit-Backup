import Foundation
import Observation
import Photos
import UserNotifications

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
  var notificationsEnabled = BackupSettings.notificationsEnabled
  var notificationAuthorization: UNAuthorizationStatus = .notDetermined
  var didCompleteOnboarding = BackupSettings.didCompleteOnboarding
  var isSignedIn = false
  var isWorking = false
  var serverReachable: Bool?
  var statusMessage: String?
  var photoStatus: PHAuthorizationStatus = .notDetermined
  var isPreview = false

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

  func restore() {
    guard !isPreview else { return }
    photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    uploadLivePhotoMovies = BackupSettings.uploadLivePhotoMovies
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
        uploadLivePhotoMovies: uploadLivePhotoMovies
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

  func refresh() async {
    guard !isPreview else { return }
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
      serverReachable = true
      let generation = recentGeneration + 1
      recentGeneration = generation
      let page = try await client.recent(limit: Self.recentPageSize)
      guard generation == recentGeneration else { return }
      replaceRecent(page.items)
      recentTotal = page.total
      await Task.yield()
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
      guard pendingScan == pendingGeneration else { return }
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

  func setUploadLivePhotoMovies(_ enabled: Bool) {
    uploadLivePhotoMovies = enabled
    guard !isPreview else { return }
    BackupSettings.setUploadLivePhotoMovies(enabled)
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
  static let homeRecentPreview = 10
  private static let pendingPageSize = 5
  private static let recentPageSize = 10
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
        pending.append(contentsOf: UploadGroups.pending(expected: slice, uploaded: stored))
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
    guard !photoLibrary.uploadJobExtensionEnabled else { return }
    do {
      try photoLibrary.enableUploadJobExtension(with: nil)
    } catch {
      statusMessage = error.localizedDescription
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
}
