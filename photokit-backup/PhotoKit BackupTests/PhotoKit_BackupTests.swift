import XCTest
@testable import PhotoKit_Backup

@MainActor
final class PhotoKit_BackupTests: XCTestCase {
    func testLivePhotoMovieUsesTheStillName() {
        XCTAssertEqual(UploadNaming.livePhotoMovieFilename(stillFilename: "IMG_2456.HEIC"), "IMG_2456.MOV")
        XCTAssertEqual(UploadNaming.livePhotoMovieFilename(stillFilename: "IMG_2456.JPG"), "IMG_2456.MOV")
    }

    func testRelativePathUsesTheCaptureMonthInTheTimestamp() {
        let zone = TimeZone(secondsFromGMT: -5 * 60 * 60)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 0, minute: 30))!
        let timestamp = UploadNaming.isoTimestamp(for: date, timeZone: zone)

        XCTAssertTrue(timestamp.hasPrefix("2024-01-01"))
        XCTAssertEqual(
            UploadNaming.relativePath(filename: "IMG_2456.HEIC", isoTimestamp: timestamp),
            "2024/01/IMG_2456.HEIC"
        )
        XCTAssertEqual(
            UploadNaming.relativePath(filename: "IMG_2456.MOV", isoTimestamp: "2026-10-20T23:30:00+02:00"),
            "2026/10/IMG_2456.MOV"
        )
    }

    func testPendingListKeepsFilesTheServerDoesNotHave() {
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

        let missing = PendingUploads.missing(expected: [photo, movie], uploaded: ["asset": ["photo"]])
        XCTAssertEqual(missing.map(\.filename), ["IMG_2456.MOV"])
    }

    func testServerAddressAcceptsHostPortAndStripsATrailingSlash() {
        XCTAssertEqual(ServerAddress.normalize("192.168.1.20:8080")?.absoluteString, "http://192.168.1.20:8080")
        XCTAssertEqual(ServerAddress.normalize("https://nas.example.com/")?.absoluteString, "https://nas.example.com")
        XCTAssertNil(ServerAddress.normalize("ftp://example.com"))
        XCTAssertNil(ServerAddress.normalize("   "))
    }
}
