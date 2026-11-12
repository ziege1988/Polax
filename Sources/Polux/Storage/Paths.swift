import Foundation
import CryptoKit

enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
    /// GitHub-Repository für die Update-Prüfung.
    static var updateRepository: String {
        Bundle.main.infoDictionary?["PoluxUpdateRepository"] as? String ?? "ziege1988/Polax"
    }
}

enum Paths {
    private static let fm = FileManager.default

    /// Basisverzeichnis – über POLUX_HOME überschreibbar (Vorschau-Rendering in CI).
    static let support: URL = {
        if let custom = ProcessInfo.processInfo.environment["POLUX_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true).appendingPathComponent("Support", isDirectory: true)
        }
        return fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Polux", isDirectory: true)
    }()

    static let caches: URL = {
        if let custom = ProcessInfo.processInfo.environment["POLUX_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true).appendingPathComponent("Caches", isDirectory: true)
        }
        return fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Polux", isDirectory: true)
    }()

    static var library: URL { support.appendingPathComponent("library.json") }
    static var likesRoot: URL { support.appendingPathComponent("Likes", isDirectory: true) }
    static var history: URL { caches.appendingPathComponent("History", isDirectory: true) }
    static var historyIndex: URL { caches.appendingPathComponent("history.json") }

    static func likes(_ collectionID: UUID) -> URL {
        likesRoot.appendingPathComponent(collectionID.uuidString, isDirectory: true)
    }

    static func ensureDirectories() {
        for dir in [support, likesRoot, caches, history] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Kurzer, dateisystemsicherer Name aus einer beliebigen ID.
    static func safeName(_ id: String) -> String {
        SHA256.hash(data: Data(id.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    static func directorySize(_ url: URL) -> Int64 {
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
