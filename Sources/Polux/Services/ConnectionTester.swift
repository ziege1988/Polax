import Foundation

/// Prüft, ob eine Bildquelle erreichbar ist und der eingetragene Schlüssel funktioniert.
/// Merkt sich außerdem Erfolge und Fehler aus dem laufenden Betrieb.
@MainActor
final class ConnectionTester: ObservableObject {
    static let shared = ConnectionTester()

    enum Status: Equatable {
        case unknown
        case missing
        case testing
        case ok(String)
        case failed(String)
    }

    @Published private var statuses: [SourceKind: Status] = [:] {
        didSet { persist() }
    }
    @Published private(set) var lastChecked: [SourceKind: Date] = [:]

    private static let storeKey = "connectionStatuses"

    init() {
        // Zuletzt bekannten Status wiederherstellen, damit nach dem Start nicht nur „Bereit“ dasteht.
        guard let saved = UserDefaults.standard.dictionary(forKey: Self.storeKey) as? [String: [String: Any]] else { return }
        var restored: [SourceKind: Status] = [:]
        var dates: [SourceKind: Date] = [:]
        for (raw, entry) in saved {
            guard let kind = SourceKind(rawValue: raw), let state = entry["state"] as? String else { continue }
            let message = entry["message"] as? String ?? ""
            restored[kind] = state == "ok" ? .ok(message) : .failed(message)
            dates[kind] = entry["date"] as? Date
        }
        statuses = restored
        lastChecked = dates
    }

    private func persist() {
        var out: [String: [String: Any]] = [:]
        for (kind, status) in statuses {
            var entry: [String: Any] = [:]
            switch status {
            case .ok(let m): entry = ["state": "ok", "message": m]
            case .failed(let m): entry = ["state": "failed", "message": m]
            default: continue
            }
            if let d = lastChecked[kind] { entry["date"] = d }
            out[kind.rawValue] = entry
        }
        UserDefaults.standard.set(out, forKey: Self.storeKey)
    }

    /// Beim Start im Hintergrund: alle eingerichteten Quellen nacheinander prüfen.
    func testAllConfigured() async {
        for kind in SourceKind.allCases where kind != .rss && Providers.hasCredentials(kind) {
            await test(kind)
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
    }

    /// Nur für das Vorschau-Rendering.
    var previewOverrides: [SourceKind: Status] = [:]

    func status(_ kind: SourceKind) -> Status {
        if let o = previewOverrides[kind] { return o }
        if !Providers.hasCredentials(kind) { return .missing }
        return statuses[kind] ?? .unknown
    }

    /// Nach Änderung eines Schlüssels: alten Status verwerfen.
    func invalidate(_ kind: SourceKind) {
        statuses[kind] = nil
        lastChecked[kind] = nil
    }

    func test(_ kind: SourceKind) async {
        guard Providers.hasCredentials(kind) else {
            statuses[kind] = .missing
            return
        }
        guard kind != .rss else { return }   // Feeds werden pro Sammlung geprüft
        statuses[kind] = .testing
        if kind == .deviantart { await DeviantArtAuth.shared.reset() }

        var probe = PhotoCollection(name: "Verbindungstest", keywords: ["portrait"])
        probe.allowNudity = false
        do {
            let results = try await Providers.provider(for: kind)
                .search(query: "portrait", collection: probe, page: 1)
            statuses[kind] = results.isEmpty
                ? .failed("Verbunden, aber keine Testtreffer – bitte später erneut testen.")
                : .ok("Verbunden · \(results.count) Testtreffer")
        } catch {
            statuses[kind] = .failed(Self.describe(error, kind))
        }
        lastChecked[kind] = Date()
    }

    /// Testet eine einzelne Feed-Adresse (Pinterest-Board oder RSS).
    static func testFeed(_ raw: String) async -> Status {
        do {
            let r = try await RSSProvider.fetchItemsDetailed(raw)
            let withImages = r.items.filter { !$0.mediaURLs.isEmpty || RSSParser.firstImage(in: $0.description) != nil }
            if r.items.isEmpty {
                return .failed("Feed ist leer – ist das Board öffentlich und enthält es Pins?")
            }
            if withImages.isEmpty { return .failed("Feed gefunden, aber ohne Bilder.") }
            return r.fromCache
                ? .ok("\(withImages.count) Bilder (Pinterest gerade langsam – gespeicherte Bilder werden genutzt)")
                : .ok("\(withImages.count) Bilder gefunden")
        } catch {
            return .failed(describe(error, .rss))
        }
    }

    func recordSuccess(_ kind: SourceKind) {
        lastChecked[kind] = Date()
        if case .ok = statuses[kind] { persist(); return }
        statuses[kind] = .ok("Verbunden")
    }

    func recordFailure(_ kind: SourceKind, _ error: Error) {
        lastChecked[kind] = Date()
        statuses[kind] = .failed(Self.describe(error, kind))
    }

    /// Übersetzt technische Fehler in verständliche Hinweise.
    static func describe(_ error: Error, _ kind: SourceKind) -> String {
        if let p = error as? ProviderError {
            switch p {
            case .http(let code, _) where code == 401 || code == 403:
                if kind == .artstation {
                    return "ArtStation blockiert die Anfrage gerade (HTTP \(code)). Später erneut versuchen."
                }
                if kind == .rss {
                    return "Pinterest verweigert den Zugriff (HTTP \(code)). Ist das Board öffentlich (nicht „geheim“)?"
                }
                return "Schlüssel ungültig oder noch nicht freigeschaltet (HTTP \(code))."
            case .http(let code, _) where code == 404:
                return kind == .rss
                    ? "Board nicht gefunden (HTTP 404) – Adresse prüfen, Format: pinterest.com/nutzer/boardname"
                    : "Schnittstelle nicht gefunden (HTTP 404)."
            case .http(let code, _) where code == 429:
                return "Anfragelimit erreicht – in einer Stunde erneut versuchen."
            case .http(let code, _) where code >= 500:
                return "Der Dienst hat gerade Probleme (HTTP \(code))."
            case .missingCredentials:
                return "Schlüssel fehlt."
            default:
                return p.localizedDescription
            }
        }
        if let u = error as? URLError {
            switch u.code {
            case .notConnectedToInternet, .networkConnectionLost: return "Keine Internetverbindung."
            case .timedOut: return "Zeitüberschreitung – der Dienst antwortet nicht."
            case .cannotFindHost, .dnsLookupFailed: return "Server nicht gefunden."
            default: return u.localizedDescription
            }
        }
        if error is DecodingError {
            return "Unerwartete Antwort – evtl. falscher Schlüssel oder geänderte Schnittstelle."
        }
        return error.localizedDescription
    }
}
