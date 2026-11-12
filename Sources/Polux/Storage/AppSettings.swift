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
    @Published var lastUpdateCheck: Date? { didSet { d.set(lastUpdateCheck, forKey: "lastUpdateCheck") } }

    private init() {
        d.register(defaults: [
            "intervalMinutes": 5,
            "isPaused": false,
            "windowLevel": WidgetLevel.desktop.rawValue,
            "polaroidSize": PolaroidSize.medium.rawValue,
            "thumbnailMaxPixel": 900,
            "thumbnailQuality": 0.6,
            "autoCheckUpdates": true
        ])
        intervalMinutes = max(1, d.integer(forKey: "intervalMinutes"))
        isPaused = d.bool(forKey: "isPaused")
        windowLevel = WidgetLevel(rawValue: d.string(forKey: "windowLevel") ?? "") ?? .desktop
        polaroidSize = PolaroidSize(rawValue: d.string(forKey: "polaroidSize") ?? "") ?? .medium
        thumbnailMaxPixel = d.integer(forKey: "thumbnailMaxPixel")
        thumbnailQuality = d.double(forKey: "thumbnailQuality")
        autoCheckUpdates = d.bool(forKey: "autoCheckUpdates")
        lastUpdateCheck = d.object(forKey: "lastUpdateCheck") as? Date
    }
}
