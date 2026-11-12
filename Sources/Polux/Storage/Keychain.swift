import Foundation
import Security

/// API-Schlüssel werden im macOS-Schlüsselbund gespeichert, nicht im Klartext.
enum CredentialKey: String, CaseIterable {
    case unsplash = "unsplash.accessKey"
    case flickr = "flickr.apiKey"
    case pexels = "pexels.apiKey"
    case deviantartID = "deviantart.clientID"
    case deviantartSecret = "deviantart.clientSecret"
}

enum Keychain {
    private static let service = "io.github.ziege1988.polux"
    private static var cache: [CredentialKey: String] = [:]
    private static let lock = NSLock()

    static func get(_ key: CredentialKey) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let v = cache[key] { return v.isEmpty ? nil : v }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key.rawValue,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        let value: String
        if status == errSecSuccess, let data = out as? Data, let s = String(data: data, encoding: .utf8) {
            value = s
        } else {
            value = ""
        }
        cache[key] = value
        return value.isEmpty ? nil : value
    }

    static func set(_ value: String, for key: CredentialKey) {
        lock.lock(); defer { lock.unlock() }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key.rawValue
        ]
        SecItemDelete(base as CFDictionary)
        if !trimmed.isEmpty {
            var add = base
            add[kSecValueData] = Data(trimmed.utf8)
            add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
        cache[key] = trimmed
    }

    static func has(_ key: CredentialKey) -> Bool { get(key) != nil }
}
