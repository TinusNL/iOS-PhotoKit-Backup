import Foundation
import Security

enum AppGroup {
    static let id = "group.com.tinus.PhotoKit-Backup"

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
              !apiKey.isEmpty else {
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

    static func signOut() {
        AppGroup.defaults.removeObject(forKey: serverURLKey)
        APIKeyStore.delete()
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
    private static let service = "com.tinus.PhotoKit-Backup"
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
