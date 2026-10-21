import Foundation

struct RemoteFile: Decodable, Identifiable, Hashable, Sendable {
  var filename: String
  var relativePath: String
  var bytes: Int
  var contentType: String?
  var createdAt: String?
  var uploadedAt: String

  var id: String { relativePath }
}

struct BackupClient: Sendable {
  var baseURL: URL
  var apiKey: String
  var session: URLSession = .shared

  func sessionName() async throws -> String {
    let (data, response) = try await session.data(for: request(path: "api/session"))
    try validate(response, data: data)
    return try JSONDecoder().decode(SessionName.self, from: data).name
  }

  func recent(limit: Int = 10, offset: Int = 0) async throws -> RecentPage {
    let (data, response) = try await session.data(
      for: request(path: "api/uploads", query: "limit=\(limit)&offset=\(offset)"))
    try validate(response, data: data)
    let decoded = try JSONDecoder().decode(UploadList.self, from: data)
    return RecentPage(items: decoded.items, total: decoded.total ?? offset + decoded.items.count)
  }

  func lookup(_ files: [ExpectedUpload]) async throws -> [String: Set<String>] {
    var uploaded: [String: Set<String>] = [:]
    let batchSize = 400
    var index = 0
    while index < files.count {
      let end = min(index + batchSize, files.count)
      let batch = files[index..<end].map {
        LookupFile(
          assetId: $0.assetId,
          resourceType: $0.resourceType,
          filename: $0.filename,
          relativePath: $0.relativePath
        )
      }
      let body = try JSONEncoder().encode(LookupBody(files: batch))
      let (data, response) = try await session.data(
        for: request(path: "api/uploads/lookup", method: "POST", body: body))
      try validate(response, data: data)
      let decoded = try JSONDecoder().decode(LookupResponse.self, from: data)
      for item in decoded.uploaded {
        uploaded[item.assetId, default: []].formUnion(item.resources)
      }
      index = end
    }
    return uploaded
  }

  private func request(
    path: String, method: String = "GET", query: String? = nil, body: Data? = nil
  ) -> URLRequest {
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
    let basePath = components.path == "/" ? "" : components.path
    components.path = basePath + "/" + path
    if let query {
      components.percentEncodedQuery = query
    }
    var request = URLRequest(url: components.url ?? baseURL)
    request.httpMethod = method
    request.timeoutInterval = 60
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    if let body {
      request.httpBody = body
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    return request
  }

  private func validate(_ response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse else {
      throw BackupClientError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      let message =
        (try? JSONDecoder().decode(ErrorBody.self, from: data).error)
        ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
      throw BackupClientError.badStatus(http.statusCode, message)
    }
  }
}

nonisolated enum UploadRequest {
  static func make(settings: BackupSettings, item: ExpectedUpload) -> URLRequest? {
    var components = URLComponents(url: settings.serverURL, resolvingAgainstBaseURL: false)
    let basePath = components?.path == "/" ? "" : (components?.path ?? "")
    components?.path = basePath + "/api/upload"
    guard let url = components?.url else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue(item.assetId, forHTTPHeaderField: "X-Asset-Id")
    request.setValue(item.resourceType, forHTTPHeaderField: "X-Resource-Type")
    request.setValue(UploadNaming.encodedFilename(item.filename), forHTTPHeaderField: "X-Filename")
    request.setValue(item.isoTimestamp, forHTTPHeaderField: "X-Created-At")
    request.setValue(
      UploadNaming.contentType(for: item.filename), forHTTPHeaderField: "Content-Type")
    return request
  }
}

private struct SessionName: Decodable {
  var name: String
}

struct RecentPage: Sendable {
  var items: [RemoteFile]
  var total: Int
}

private struct UploadList: Decodable {
  var items: [RemoteFile]
  var total: Int?
}

private struct LookupBody: Encodable {
  var files: [LookupFile]
}

private struct LookupFile: Encodable {
  var assetId: String
  var resourceType: String
  var filename: String
  var relativePath: String
}

private struct LookupResponse: Decodable {
  var uploaded: [LookupHit]
}

private struct LookupHit: Decodable {
  var assetId: String
  var resources: [String]
}

private struct ErrorBody: Decodable {
  var error: String
}

enum BackupClientError: Error, LocalizedError {
  case badStatus(Int, String)
  case invalidResponse

  var errorDescription: String? {
    switch self {
    case .badStatus(let status, let message):
      return "The server returned \(status): \(message)"
    case .invalidResponse:
      return "The server returned an unexpected response."
    }
  }
}
