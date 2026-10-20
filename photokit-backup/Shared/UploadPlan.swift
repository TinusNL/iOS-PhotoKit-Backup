import Foundation

enum UploadNaming {
    static func livePhotoMovieFilename(stillFilename: String) -> String {
        let stem = URL(fileURLWithPath: stillFilename).deletingPathExtension().lastPathComponent
        return (stem.isEmpty ? "IMG" : stem) + ".MOV"
    }

    static func isoTimestamp(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func relativePath(filename: String, isoTimestamp: String) -> String {
        guard let match = isoTimestamp.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) else {
            return "1970/01/\(filename)"
        }
        let parts = isoTimestamp[match].split(separator: "-")
        return "\(parts[0])/\(parts[1])/\(filename)"
    }

    static func contentType(for filename: String) -> String {
        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "heic", "heif":
            return "image/heic"
        case "png":
            return "image/png"
        case "mov":
            return "video/quicktime"
        case "mp4":
            return "video/mp4"
        default:
            return "application/octet-stream"
        }
    }

    static func encodedFilename(_ filename: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return filename.addingPercentEncoding(withAllowedCharacters: allowed) ?? filename
    }
}

struct ExpectedUpload: Hashable, Identifiable, Sendable {
    var assetId: String
    var resourceType: String
    var filename: String
    var relativePath: String
    var isoTimestamp: String

    var id: String { key }
    var key: String { "\(assetId)|\(resourceType)" }
}

enum PendingUploads {
    static func missing(expected: [ExpectedUpload], uploaded: [String: Set<String>]) -> [ExpectedUpload] {
        expected.filter { item in
            uploaded[item.assetId]?.contains(item.resourceType) != true
        }
    }
}

enum ServerAddress {
    static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            text = "http://" + text
        }
        while text.hasSuffix("/") {
            text.removeLast()
        }
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty,
              let url = components.url else {
            return nil
        }
        var normalized = url.absoluteString
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return URL(string: normalized)
    }
}
