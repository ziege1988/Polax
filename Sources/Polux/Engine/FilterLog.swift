import Foundation

/// Protokoll der letzten Suchen je Sammlung: was gefunden, gezeigt und warum aussortiert wurde.
@MainActor
final class FilterLog: ObservableObject {
    static let shared = FilterLog()

    struct Search: Identifiable {
        let id = UUID()
        let date: Date
        let source: SourceKind
        let query: String
        let received: Int
        let accepted: Int
        let rejected: [String: Int]
        let error: String?
    }

    struct Summary {
        var searches: [Search] = []
        /// Summe aller Ablehnungsgründe (Tags + Bilderkennung) seit dem Start.
        var reasons: [String: Int] = [:]
        var received = 0
        var accepted = 0
        var imagesChecked = 0
        var shown = 0
        var since = Date()
    }

    @Published private(set) var summaries: [UUID: Summary] = [:]
    private let maxSearches = 30

    func summary(_ id: UUID) -> Summary { summaries[id] ?? Summary() }

    func recordSearch(_ id: UUID, source: SourceKind, query: String, received: Int, accepted: Int,
                      rejected: [String: Int], error: String?) {
        var s = summary(id)
        s.searches.insert(Search(date: Date(), source: source, query: query, received: received,
                                 accepted: accepted, rejected: rejected, error: error), at: 0)
        if s.searches.count > maxSearches { s.searches.removeLast(s.searches.count - maxSearches) }
        s.received += received
        s.accepted += accepted
        for (k, v) in rejected where k != FilterReason.seen { s.reasons[k, default: 0] += v }
        summaries[id] = s
    }

    func recordImageChecks(_ id: UUID, checked: Int, rejected: [String: Int]) {
        var s = summary(id)
        s.imagesChecked += checked
        for (k, v) in rejected { s.reasons[k, default: 0] += v }
        summaries[id] = s
    }

    func recordShown(_ id: UUID) {
        var s = summary(id)
        s.shown += 1
        summaries[id] = s
    }

    func reset(_ id: UUID) { summaries[id] = Summary() }

    /// Häufigster Ablehnungsgrund.
    func topReason(_ id: UUID) -> (String, Int)? {
        summary(id).reasons.max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }

    /// Konkreter Hinweis, wenn keine passenden Fotos gefunden wurden.
    func emptyHint(_ id: UUID, collection: PhotoCollection?) -> String {
        let s = summary(id)
        let usable = collection.map { c in c.sources.filter { Providers.isUsable($0, for: c) }.count } ?? 0
        if let recent = s.searches.first, recent.error != nil, s.accepted == 0 {
            return "Quellen gerade nicht erreichbar"
        }
        if let top = topReason(id) {
            switch top.0 {
            case FilterReason.keyword: return "Keine Treffer zu den Schlagwörtern – mehr Schlagwörter?"
            case FilterReason.noPerson, FilterReason.place: return "Kaum Fotos mit Personen gefunden"
            default: break
            }
        }
        if usable <= 1 { return "Nur eine Quelle aktiv – weitere einrichten" }
        return "Keine passenden Fotos – Protokoll ansehen"
    }

    /// Verständliche Tipps auf Basis der Statistik.
    func tips(_ id: UUID, collection: PhotoCollection) -> [String] {
        let s = summary(id)
        var tips: [String] = []
        let usable = collection.sources.filter { Providers.isUsable($0, for: collection) }
        if usable.count <= 1 {
            tips.append("Nur eine Bildquelle liefert. DeviantArt oder Flickr mit Schlüssel bringen deutlich mehr passende Fotos.")
        }
        let total = max(1, s.reasons.values.reduce(0, +))
        if let kw = s.reasons[FilterReason.keyword], Double(kw) / Double(total) > 0.5 {
            tips.append("Die meisten Treffer passen nicht zu den Schlagwörtern. Mehr oder etwas allgemeinere Schlagwörter helfen (z. B. zusätzlich „gothic portrait“ zu „editorial gothic“).")
        }
        if let np = s.reasons[FilterReason.noPerson], Double(np) / Double(total) > 0.3 {
            tips.append("Viele Treffer zeigen keine Person. Schlagwörter mit „portrait“, „model“ oder „woman“ liefern mehr Menschen.")
        }
        let failing = s.searches.filter { $0.error != nil }.map { $0.source.title }
        if !failing.isEmpty {
            tips.append("Fehler bei: \(Array(Set(failing)).sorted().joined(separator: ", ")). Unter „Zugänge & Quellen“ prüfen.")
        }
        return tips
    }
}
