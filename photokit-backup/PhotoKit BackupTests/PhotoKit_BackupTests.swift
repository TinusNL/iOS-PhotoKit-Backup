import XCTest

@testable import PhotoKit_Backup

@MainActor
final class PhotoKit_BackupTests: XCTestCase {
  func testLivePhotoMovieUsesTheStillName() {
    XCTAssertEqual(
      UploadNaming.livePhotoMovieFilename(stillFilename: "IMG_2456.HEIC"), "IMG_2456.MOV")
    XCTAssertEqual(
      UploadNaming.livePhotoMovieFilename(stillFilename: "IMG_2456.JPG"), "IMG_2456.MOV")
  }

  func testRelativePathUsesTheCaptureMonthInTheTimestamp() {
    let zone = TimeZone(secondsFromGMT: -5 * 60 * 60)!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let date = calendar.date(
      from: DateComponents(year: 2024, month: 1, day: 1, hour: 0, minute: 30))!
    let timestamp = UploadNaming.isoTimestamp(for: date, timeZone: zone)

    XCTAssertTrue(timestamp.hasPrefix("2024-01-01"))
    XCTAssertEqual(
      UploadNaming.relativePath(filename: "IMG_2456.HEIC", isoTimestamp: timestamp),
      "2024/01/IMG_2456.HEIC"
    )
    XCTAssertEqual(
      UploadNaming.relativePath(
        filename: "IMG_2456.MOV", isoTimestamp: "2026-10-20T23:30:00+02:00"),
      "2026/10/IMG_2456.MOV"
    )
  }

  func testPendingListKeepsFilesTheServerDoesNotHave() {
    let photo = ExpectedUpload(
      assetId: "asset",
      resourceType: "photo",
      filename: "IMG_2456.HEIC",
      relativePath: "2026/10/IMG_2456.HEIC",
      isoTimestamp: "2026-10-20T12:00:00+02:00",
      bytes: 10
    )
    let movie = ExpectedUpload(
      assetId: "asset",
      resourceType: "pairedVideo",
      filename: "IMG_2456.MOV",
      relativePath: "2026/10/IMG_2456.MOV",
      isoTimestamp: "2026-10-20T12:00:00+02:00",
      bytes: 20
    )

    let missing = PendingUploads.missing(expected: [photo, movie], uploaded: ["asset": ["photo"]])
    XCTAssertEqual(missing.map(\.filename), ["IMG_2456.MOV"])

    let partial = UploadGroups.pending(expected: [photo, movie], uploaded: ["asset": ["photo"]])
    XCTAssertEqual(partial.map(\.title), ["IMG_2456.MOV"])
    XCTAssertEqual(partial.first?.bytes, 20)
    XCTAssertEqual(partial.first?.isLivePhoto, true)

    let waiting = UploadGroups.pending(expected: [photo, movie], uploaded: [:])
    XCTAssertEqual(waiting.map(\.title), ["IMG_2456.HEIC"])
    XCTAssertEqual(waiting.first?.bytes, 30)
    XCTAssertEqual(waiting.first?.isLivePhoto, true)

    let done = UploadGroups.pending(
      expected: [photo, movie], uploaded: ["asset": ["photo", "pairedVideo"]])
    XCTAssertTrue(done.isEmpty)
  }

  func testRecentListMergesALivePhoto() {
    let photo = ExpectedUpload(
      assetId: "asset",
      resourceType: "photo",
      filename: "IMG_2456.HEIC",
      relativePath: "2026/10/IMG_2456.HEIC",
      isoTimestamp: "2026-10-20T12:00:00+02:00"
    )
    let movie = ExpectedUpload(
      assetId: "asset",
      resourceType: "pairedVideo",
      filename: "IMG_2456.MOV",
      relativePath: "2026/10/IMG_2456.MOV",
      isoTimestamp: "2026-10-20T12:00:00+02:00"
    )
    let still = RemoteFile(
      filename: "IMG_2456.HEIC", relativePath: "2026/10/IMG_2456.HEIC", bytes: 10,
      contentType: "image/heic", createdAt: nil, uploadedAt: "2026-10-20T12:04:00.000Z")
    let paired = RemoteFile(
      filename: "IMG_2456.MOV", relativePath: "2026/10/IMG_2456.MOV", bytes: 20,
      contentType: "video/quicktime", createdAt: nil, uploadedAt: "2026-10-20T12:05:00.000Z")
    let jpg = RemoteFile(
      filename: "IMG_2450.JPG", relativePath: "2019/03/IMG_2450.JPG", bytes: 5,
      contentType: "image/jpeg", createdAt: nil, uploadedAt: "2026-10-19T18:12:00.000Z")

    let both = UploadGroups.recent(files: [still, paired, jpg], library: [photo, movie])
    XCTAssertEqual(both.map(\.title), ["IMG_2456.HEIC", "IMG_2450.JPG"])
    XCTAssertEqual(both.first?.bytes, 30)
    XCTAssertEqual(both.first?.isLivePhoto, true)
    XCTAssertEqual(both.last?.isLivePhoto, false)

    let half = UploadGroups.recent(files: [still], library: [photo, movie])
    XCTAssertEqual(half.map(\.title), ["IMG_2456.HEIC"])

    var inserted: [ListedUpload] = []
    inserted = UploadGroups.insertRecent(file: still, assetId: "asset", into: inserted)
    inserted = UploadGroups.insertRecent(file: paired, assetId: "asset", into: inserted)
    inserted = UploadGroups.insertRecent(file: jpg, assetId: "other", into: inserted)
    XCTAssertEqual(inserted.map(\.title), ["IMG_2450.JPG", "IMG_2456.HEIC"])
    XCTAssertEqual(inserted[1].bytes, 30)
    XCTAssertTrue(inserted[1].isLivePhoto)
    XCTAssertFalse(inserted[0].isLivePhoto)
  }

  func testUploadSummaryNamesOneFileAndCountsTheRest() {
    XCTAssertEqual(
      UploadSummary.body(total: 1, filename: "IMG_2456.HEIC"), "Backed up IMG_2456.HEIC.")
    XCTAssertEqual(UploadSummary.body(total: 1, filename: nil), "Backed up 1 file.")
    XCTAssertEqual(UploadSummary.body(total: 12, filename: "IMG_2456.HEIC"), "Backed up 12 files.")
  }

  func testUploadFailureNoticeNamesOneFileAndCountsTheRest() {
    XCTAssertEqual(
      UploadFailureNotice.body(total: 1, filename: "IMG_2456.HEIC"),
      "Couldn't back up IMG_2456.HEIC.")
    XCTAssertEqual(UploadFailureNotice.body(total: 1, filename: nil), "Couldn't back up 1 file.")
    XCTAssertEqual(
      UploadFailureNotice.body(total: 3, filename: "IMG_2456.HEIC"), "Couldn't back up 3 files.")
  }

  func testServerAddressAcceptsHostPortAndStripsATrailingSlash() {
    XCTAssertEqual(
      ServerAddress.normalize("192.168.1.20:8080")?.absoluteString, "http://192.168.1.20:8080")
    XCTAssertEqual(
      ServerAddress.normalize("https://nas.example.com/")?.absoluteString, "https://nas.example.com"
    )
    XCTAssertNil(ServerAddress.normalize("ftp://example.com"))
    XCTAssertNil(ServerAddress.normalize("   "))
  }

  func testFastBackupCopyDescribesPhotosAndVideos() {
    let video = ListedUpload(
      id: "video", assetId: "video", title: "IMG_3104.MP4", subtitle: "2026/10/IMG_3104.MP4",
      bytes: 10)
    let movie = ListedUpload(
      id: "movie", assetId: "movie", title: "IMG_3102.MOV", subtitle: "2026/10/IMG_3102.MOV",
      bytes: 20)
    let photo = ListedUpload(
      id: "photo", assetId: "photo", title: "IMG_2450.JPG", subtitle: "2019/03/IMG_2450.JPG",
      bytes: 5)

    XCTAssertEqual(FastBackupCopy.waitingLine(for: [video, movie]), "2 videos waiting to upload")
    XCTAssertEqual(FastBackupCopy.uploadingLine(for: [video, movie]), "Uploading 2 videos")
    XCTAssertEqual(
      FastBackupCopy.waitingLine(for: [photo, video]), "1 photo and 1 video waiting to upload")
    XCTAssertEqual(FastBackupCopy.completedLine(done: 0, total: 2), "0 of 2 items completed")
    XCTAssertEqual(FastBackupCopy.uploadingCount(2), "2 uploading")
    XCTAssertEqual(FastBackupCopy.percent(180, 400), 45)
  }
}
