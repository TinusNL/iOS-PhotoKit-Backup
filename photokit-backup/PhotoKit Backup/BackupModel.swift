import Foundation
import Observation
import Photos

@MainActor
@Observable
final class BackupModel {
  var serverField = ""
  var apiKeyField = ""
  var accountName = ""
  var recent: [RemoteFile] = []
  var recentTotal = 0
  var isLoadingMoreRecent = false
  var pending: [ExpectedUpload] = []
  var uploadLivePhotoMovies = true
  var isSignedIn = false
  var isWorking = false
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
    model.recent = [
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
    model.recentTotal = model.recent.count
    model.pending = [
      ExpectedUpload(
        assetId: "preview-live", resourceType: "photo", filename: "IMG_3102.HEIC",
        relativePath: "2026/10/IMG_3102.HEIC", isoTimestamp: "2026-10-20T15:02:00+02:00"),
      ExpectedUpload(
        assetId: "preview-live", resourceType: "pairedVideo", filename: "IMG_3102.MOV",
        relativePath: "2026/10/IMG_3102.MOV", isoTimestamp: "2026-10-20T15:02:00+02:00"),
      ExpectedUpload(
        assetId: "preview-video", resourceType: "video", filename: "IMG_3104.MP4",
        relativePath: "2026/10/IMG_3104.MP4", isoTimestamp: "2026-10-18T09:41:00+02:00"),
    ]
    return model
  }

  func restore() {
    guard !isPreview else { return }
    photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    uploadLivePhotoMovies = BackupSettings.uploadLivePhotoMovies
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
      isSignedIn = true
      await enableUploadsIfAuthorized()
      await refresh()
    } catch {
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
      let generation = recentGeneration + 1
      recentGeneration = generation
      let page = try await client.recent(limit: Self.recentPageSize)
      guard generation == recentGeneration else { return }
      recent = page.items
      recentTotal = page.total
      await Task.yield()
      let expected = LibraryScanner.expected(uploadLivePhotoMovies: settings.uploadLivePhotoMovies)
      let stored = try await client.lookup(expected)
      pending = PendingUploads.missing(expected: expected, uploaded: stored)
      statusMessage = nil
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  func loadMoreRecent() async {
    guard !isPreview, !isWorking, !isLoadingMoreRecent, recent.count < recentTotal else { return }
    guard let settings = BackupSettings.load() else { return }
    isLoadingMoreRecent = true
    let generation = recentGeneration
    let offset = recent.count
    defer { isLoadingMoreRecent = false }
    do {
      let page = try await BackupClient(baseURL: settings.serverURL, apiKey: settings.apiKey)
        .recent(
          limit: Self.recentPageSize,
          offset: offset
        )
      guard generation == recentGeneration else { return }
      recentTotal = page.total
      let known = Set(recent.map(\.id))
      recent.append(contentsOf: page.items.filter { !known.contains($0.id) })
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  func setUploadLivePhotoMovies(_ enabled: Bool) {
    uploadLivePhotoMovies = enabled
    guard !isPreview else { return }
    BackupSettings.setUploadLivePhotoMovies(enabled)
  }

  func signOut() {
    guard !isPreview else {
      isSignedIn = false
      accountName = ""
      recent = []
      recentTotal = 0
      pending = []
      return
    }
    let library = PHPhotoLibrary.shared()
    if library.uploadJobExtensionEnabled {
      try? library.disableUploadJobExtension()
    }
    BackupSettings.signOut()
    apiKeyField = ""
    accountName = ""
    recentGeneration += 1
    recent = []
    recentTotal = 0
    pending = []
    isSignedIn = false
    statusMessage = nil
  }

  private static let recentPageSize = 40
  private var recentGeneration = 0

  private func enableUploadsIfAuthorized() async {
    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    photoStatus = status
    guard status == .authorized else { return }
    let library = PHPhotoLibrary.shared()
    guard !library.uploadJobExtensionEnabled else { return }
    do {
      try library.enableUploadJobExtension(with: nil)
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
