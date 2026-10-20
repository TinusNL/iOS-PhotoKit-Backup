import Foundation
import Security

enum AppGroup {
  static let id = "group.com.tinusnl.photokit-backup"

  static var defaults: UserDefaults {
    UserDefaults(suiteName: id) ?? .standard
  }
}

struct BackupSettings: Equatable, Sendable {
  var serverURL: URL
  var apiKey: String
  var uploadLivePhotoMovies: Bool

  static let livePhotoKey = "uploadLivePhotoMovies"
  static let serverURLKey = "serverURL"

  static var uploadLivePhotoMovies: Bool {
    if AppGroup.defaults.object(forKey: livePhotoKey) == nil {
      return true
    }
    return AppGroup.defaults.bool(forKey: livePhotoKey)
  }

  static var hasServer: Bool {
    guard let raw = AppGroup.defaults.string(forKey: serverURLKey) else { return false }
    return ServerAddress.normalize(raw) != nil
  }

  static func load() -> BackupSettings? {
    guard let raw = AppGroup.defaults.string(forKey: serverURLKey),
      let serverURL = ServerAddress.normalize(raw),
      let apiKey = APIKeyStore.load(),
      !apiKey.isEmpty
    else {
      return nil
    }
    return BackupSettings(
      serverURL: serverURL,
      apiKey: apiKey,
      uploadLivePhotoMovies: uploadLivePhotoMovies
    )
  }

  func save() throws {
    AppGroup.defaults.set(serverURL.absoluteString, forKey: Self.serverURLKey)
    AppGroup.defaults.set(uploadLivePhotoMovies, forKey: Self.livePhotoKey)
    try APIKeyStore.save(apiKey)
  }

  static func setUploadLivePhotoMovies(_ enabled: Bool) {
    AppGroup.defaults.set(enabled, forKey: livePhotoKey)
  }

  static let notificationsKey = "notificationsEnabled"
  static let onboardingKey = "didCompleteOnboarding"

  static var notificationsEnabled: Bool {
    AppGroup.defaults.bool(forKey: notificationsKey)
  }

  static func setNotificationsEnabled(_ enabled: Bool) {
    AppGroup.defaults.set(enabled, forKey: notificationsKey)
    if !enabled {
      UploadSummary.reset()
      UploadFailureNotice.reset()
    }
  }

  static var didCompleteOnboarding: Bool {
    AppGroup.defaults.bool(forKey: onboardingKey)
  }

  static func setDidCompleteOnboarding(_ completed: Bool) {
    AppGroup.defaults.set(completed, forKey: onboardingKey)
  }

  static func signOut() {
    AppGroup.defaults.removeObject(forKey: serverURLKey)
    APIKeyStore.delete()
  }
}

enum UploadSummary {
  private static let countKey = "notificationSummaryCount"
  private static let postedCountKey = "notificationSummaryPostedCount"
  private static let postedAtKey = "notificationSummaryPostedAt"
  private static let filenameKey = "notificationSummaryFilename"
  private static let minimumInterval: TimeInterval = 60

  static func body(total: Int, filename: String?) -> String {
    if total == 1 {
      if let filename, !filename.isEmpty {
        return "Backed up \(filename)."
      }
      return "Backed up 1 file."
    }
    return "Backed up \(total) files."
  }

  static func record(_ filenames: [String]) {
    guard BackupSettings.notificationsEnabled, !filenames.isEmpty else { return }
    let defaults = AppGroup.defaults
    if defaults.string(forKey: filenameKey) == nil,
      let filename = filenames.first(where: { !$0.isEmpty })
    {
      defaults.set(filename, forKey: filenameKey)
    }
    defaults.set(defaults.integer(forKey: countKey) + filenames.count, forKey: countKey)
  }

  static func messageIfDue(force: Bool, now: Date = Date()) -> String? {
    guard BackupSettings.notificationsEnabled else { return nil }
    let defaults = AppGroup.defaults
    let count = defaults.integer(forKey: countKey)
    let postedCount = defaults.integer(forKey: postedCountKey)
    guard count > postedCount else { return nil }
    let postedAt = defaults.object(forKey: postedAtKey) as? Date ?? .distantPast
    let due = force || postedCount == 0 || now.timeIntervalSince(postedAt) >= minimumInterval
    guard due else { return nil }
    defaults.set(now, forKey: postedAtKey)
    defaults.set(count, forKey: postedCountKey)
    return body(total: count, filename: defaults.string(forKey: filenameKey))
  }

  static func reset() {
    let defaults = AppGroup.defaults
    defaults.set(0, forKey: countKey)
    defaults.set(0, forKey: postedCountKey)
    defaults.removeObject(forKey: postedAtKey)
    defaults.removeObject(forKey: filenameKey)
  }
}

enum UploadFailureNotice {
  private static let countKey = "notificationFailureCount"
  private static let postedCountKey = "notificationFailurePostedCount"
  private static let filenameKey = "notificationFailureFilename"

  static func body(total: Int, filename: String?) -> String {
    if total == 1 {
      if let filename, !filename.isEmpty {
        return "Couldn't back up \(filename)."
      }
      return "Couldn't back up 1 file."
    }
    return "Couldn't back up \(total) files."
  }

  static func record(_ filenames: [String]) {
    guard BackupSettings.notificationsEnabled, !filenames.isEmpty else { return }
    let defaults = AppGroup.defaults
    if defaults.string(forKey: filenameKey) == nil,
      let filename = filenames.first(where: { !$0.isEmpty })
    {
      defaults.set(filename, forKey: filenameKey)
    }
    defaults.set(defaults.integer(forKey: countKey) + filenames.count, forKey: countKey)
  }

  static func message() -> String? {
    guard BackupSettings.notificationsEnabled else { return nil }
    let defaults = AppGroup.defaults
    let count = defaults.integer(forKey: countKey)
    guard count > defaults.integer(forKey: postedCountKey) else { return nil }
    defaults.set(count, forKey: postedCountKey)
    return body(total: count, filename: defaults.string(forKey: filenameKey))
  }

  static func reset() {
    let defaults = AppGroup.defaults
    defaults.set(0, forKey: countKey)
    defaults.set(0, forKey: postedCountKey)
    defaults.removeObject(forKey: filenameKey)
  }
}

enum FailureLedger {
  private static let key = "uploadFailures"
  private static let cooldown: TimeInterval = 6 * 60 * 60

  static func shouldSkip(_ id: String, now: Date = Date()) -> Bool {
    guard let stamp = map()[id] else { return false }
    return now.timeIntervalSince1970 - stamp < cooldown
  }

  static func record(_ id: String, now: Date = Date()) {
    var stored = map()
    stored[id] = now.timeIntervalSince1970
    AppGroup.defaults.set(stored, forKey: key)
  }

  static func clear(_ id: String) {
    var stored = map()
    stored.removeValue(forKey: id)
    AppGroup.defaults.set(stored, forKey: key)
  }

  private static func map() -> [String: Double] {
    AppGroup.defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
  }
}

enum APIKeyStore {
  private static let service = "com.tinusnl.photokit-backup"
  private static let account = "apiKey"

  static func save(_ key: String) throws {
    delete()
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: Data(key.utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw APIKeyStoreError(status: status)
    }
  }

  static func load() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func delete() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
  }
}

struct APIKeyStoreError: Error, LocalizedError {
  var status: OSStatus

  var errorDescription: String? {
    "Could not store the API key (keychain status \(status))."
  }
}
