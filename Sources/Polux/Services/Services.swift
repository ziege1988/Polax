import Foundation
import AppKit
import ServiceManagement

/// Autostart beim Anmelden (macOS 13+: SMAppService).
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
            return true
        } catch {
            NSLog("Polux: Autostart konnte nicht geändert werden: \(error)")
            return false
        }
    }

    /// Beim ersten Start automatisch aktivieren.
    static func enableOnFirstRun() {
        let key = "didConfigureLaunchAtLogin"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        if set(true) { UserDefaults.standard.set(true, forKey: key) }
    }
}

/// Prüft GitHub-Releases auf neuere Versionen.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    var availableVersion: String? {
        if case .available(let v, _) = state { return v }
        return nil
    }

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
        let assets: [Asset]?
        struct Asset: Decodable { let name: String; let browser_download_url: String }
    }

    func check() async {
        state = .checking
        let url = URL(string: "https://api.github.com/repos/\(AppInfo.updateRepository)/releases/latest")!
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await HTTP.session.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 404 {
                state = .failed("Noch keine veröffentlichte Version gefunden (oder das Repository ist privat).")
                return
            }
            guard (200..<300).contains(code) else {
                state = .failed("GitHub antwortet mit HTTP \(code).")
                return
            }
            let rel = try JSONDecoder().decode(Release.self, from: data)
            AppSettings.shared.lastUpdateCheck = Date()
            let latest = rel.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            if Self.isVersion(latest, newerThan: AppInfo.version) {
                let zip = rel.assets?.first { $0.name.lowercased().hasSuffix(".zip") }
                let target = zip.flatMap { URL(string: $0.browser_download_url) } ?? URL(string: rel.html_url)!
                state = .available(version: latest, url: target)
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Höchstens einmal täglich automatisch prüfen.
    func checkIfDue() async {
        guard AppSettings.shared.autoCheckUpdates else { return }
        if let last = AppSettings.shared.lastUpdateCheck, Date().timeIntervalSince(last) < 24 * 3600 { return }
        await check()
    }

    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(whereSeparator: { !$0.isNumber }).map { Int($0) ?? 0 }
        }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

enum SettingsTab: String, Hashable {
    case collections, sources, general, updates
}

/// Öffnet Fenster aus SwiftUI-Ansichten heraus (wird vom AppDelegate verdrahtet).
final class Router {
    static let shared = Router()
    var openGallery: (UUID) -> Void = { _ in }
    var openSettings: (SettingsTab) -> Void = { _ in }
    var resetPosition: () -> Void = {}
}
