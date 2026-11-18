import Foundation
import Combine

/// Globale Einstellungen, persistiert in UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var intervalMinutes: Int { didSet { d.set(intervalMinutes, forKey: "intervalMinutes") } }
    @Published var isPaused: Bool { didSet { d.set(isPaused, forKey: "isPaused") } }
    @Published var windowLevel: WidgetLevel { didSet { d.set(windowLevel.rawValue, forKey: "windowLevel") } }
    @Published var polaroidSize: PolaroidSize { didSet { d.set(polaroidSize.rawValue, forKey: "polaroidSize") } }
    /// Längste Kante der gespeicherten Like-Vorschaubilder.
    @Published var thumbnailMaxPixel: Int { didSet { d.set(thumbnailMaxPixel, forKey: "thumbnailMaxPixel") } }
    @Published var thumbnailQuality: Double { didSet { d.set(thumbnailQuality, forKey: "thumbnailQuality") } }
    @Published var autoCheckUpdates: Bool { didSet { d.set(autoCheckUpdates, forKey: "autoCheckUpdates") } }
    /// Neue Versionen ohne Rückfrage installieren (beim Start bzw. alle paar Stunden).
    @Published var autoInstallUpdates: Bool { didSet { d.set(autoInstallUpdates, forKey: "autoInstallUpdates") } }
    @Published var lastUpdateCheck: Date? { didSet { d.set(lastUpdateCheck, forKey: "lastUpdateCheck") } }
    /// Wöchentliche automatische Sicherung in iCloud Drive.
    @Published var autoBackupToICloud: Bool { didSet { d.set(autoBackupToICloud, forKey: "autoBackupToICloud") } }
    @Published var lastBackup: Date? { didSet { d.set(lastBackup, forKey: "lastBackup") } }

    private init() {
        d.register(defaults: [
            "intervalMinutes": 5,
            "isPaused": false,
            "windowLevel": WidgetLevel.desktop.rawValue,
            "polaroidSize": PolaroidSize.medium.rawValue,
            "thumbnailMaxPixel": 900,
            "thumbnailQuality": 0.6,
            "autoCheckUpdates": true,
            "autoInstallUpdates": true
        ])
        intervalMinutes = max(1, d.integer(forKey: "intervalMinutes"))
        isPaused = d.bool(forKey: "isPaused")
        windowLevel = WidgetLevel(rawValue: d.string(forKey: "windowLevel") ?? "") ?? .desktop
        polaroidSize = PolaroidSize(rawValue: d.string(forKey: "polaroidSize") ?? "") ?? .medium
        thumbnailMaxPixel = d.integer(forKey: "thumbnailMaxPixel")
        thumbnailQuality = d.double(forKey: "thumbnailQuality")
        autoCheckUpdates = d.bool(forKey: "autoCheckUpdates")
        autoInstallUpdates = d.bool(forKey: "autoInstallUpdates")
        lastUpdateCheck = d.object(forKey: "lastUpdateCheck") as? Date
        autoBackupToICloud = d.bool(forKey: "autoBackupToICloud")
        lastBackup = d.object(forKey: "lastBackup") as? Date
    }
}
