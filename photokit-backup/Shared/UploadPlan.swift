import Foundation

nonisolated enum UploadNaming {
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
    guard let match = isoTimestamp.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression)
    else {
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

nonisolated struct ExpectedUpload: Hashable, Identifiable, Sendable {
  var assetId: String
  var resourceType: String
  var filename: String
  var relativePath: String
  var isoTimestamp: String
  var bytes: Int? = nil

  var id: String { key }
  var key: String { "\(assetId)|\(resourceType)" }
}

enum PendingUploads {
  static func missing(expected: [ExpectedUpload], uploaded: [String: Set<String>])
    -> [ExpectedUpload]
  {
    expected.filter { item in
      uploaded[item.assetId]?.contains(item.resourceType) != true
    }
  }
}

nonisolated struct ListedUpload: Identifiable, Hashable, Sendable {
  var id: String
  var assetId: String
  var title: String
  var subtitle: String
  var bytes: Int?
  var isLivePhoto: Bool = false
}

enum UploadGroups {
  private static let stillExtensions: Set<String> = ["heic", "heif", "jpg", "jpeg", "png"]

  static func pending(expected: [ExpectedUpload], uploaded: [String: Set<String>]) -> [ListedUpload]
  {
    let missing = PendingUploads.missing(expected: expected, uploaded: uploaded)
    var order: [String] = []
    var buckets: [String: [ExpectedUpload]] = [:]
    for item in missing {
      if buckets[item.assetId] == nil {
        order.append(item.assetId)
      }
      buckets[item.assetId, default: []].append(item)
    }

    return order.flatMap { assetId in
      let items = buckets[assetId] ?? []
      let photo = items.first { $0.resourceType == "photo" }
      if let photo, items.contains(where: { $0.resourceType == "pairedVideo" }) {
        return [
          ListedUpload(
            id: assetId,
            assetId: assetId,
            title: photo.filename,
            subtitle: photo.relativePath,
            bytes: totalBytes(items),
            isLivePhoto: true
          )
        ]
      }
      return items.map { item in
        ListedUpload(
          id: item.key,
          assetId: item.assetId,
          title: item.filename,
          subtitle: item.relativePath,
          bytes: item.bytes,
          isLivePhoto: item.resourceType == "pairedVideo"
        )
      }
    }
  }

  static func recent(files: [RemoteFile], library: [ExpectedUpload]) -> [ListedUpload] {
    let assetByFilename = assetIds(in: library)
    let paired = pairedStems(in: files)
    var rows: [ListedUpload] = []
    for file in files {
      let stem = stemKey(folderAndName: file)
      if fileExtension(file.filename) == "mov", paired.contains(stem) {
        continue
      }
      let partners =
        paired.contains(stem) ? files.filter { stemKey(folderAndName: $0) == stem } : [file]
      let primary = partners.first { stillExtensions.contains(fileExtension($0.filename)) } ?? file
      rows.append(
        ListedUpload(
          id: paired.contains(stem) ? "live:\(stem)" : file.relativePath,
          assetId: assetByFilename[filenameKey(primary.filename)] ?? "",
          title: primary.filename,
          subtitle: primary.relativePath,
          bytes: partners.reduce(0) { $0 + $1.bytes },
          isLivePhoto: paired.contains(stem)
        )
      )
    }
    return rows
  }

  private static func totalBytes(_ items: [ExpectedUpload]) -> Int? {
    let known = items.compactMap(\.bytes)
    guard !known.isEmpty else { return nil }
    return known.reduce(0, +)
  }

  private static func assetIds(in library: [ExpectedUpload]) -> [String: String] {
    var assetByFilename: [String: String] = [:]
    for item in library {
      assetByFilename[filenameKey(item.filename)] = item.assetId
    }
    return assetByFilename
  }

  private static func pairedStems(in files: [RemoteFile]) -> Set<String> {
    var stills: Set<String> = []
    var movies: Set<String> = []
    for file in files {
      let key = stemKey(folderAndName: file)
      if stillExtensions.contains(fileExtension(file.filename)) {
        stills.insert(key)
      } else if fileExtension(file.filename) == "mov" {
        movies.insert(key)
      }
    }
    return stills.intersection(movies)
  }

  private static func stemKey(folderAndName file: RemoteFile) -> String {
    let folder = (file.relativePath as NSString).deletingLastPathComponent
    let stem = URL(fileURLWithPath: file.filename).deletingPathExtension().lastPathComponent
    return "\(folder)/\(filenameKey(stem))"
  }

  private static func fileExtension(_ filename: String) -> String {
    URL(fileURLWithPath: filename).pathExtension.lowercased()
  }

  private static func filenameKey(_ filename: String) -> String {
    filename.precomposedStringWithCanonicalMapping.lowercased()
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
      let url = components.url
    else {
      return nil
    }
    var normalized = url.absoluteString
    while normalized.hasSuffix("/") {
      normalized.removeLast()
    }
    return URL(string: normalized)
  }
}
