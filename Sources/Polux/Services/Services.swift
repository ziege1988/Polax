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
