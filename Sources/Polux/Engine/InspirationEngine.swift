import AppKit
import Combine
import SwiftUI

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var candidate: PhotoCandidate
    var collectionID: UUID
    var fileName: String
    var analysis: ImageAnalysis?
    var shownAt = Date()
}

/// Steuert den Bildwechsel: Vorschläge holen, nach Stil auswählen, anzeigen, Likes speichern.
@MainActor
final class InspirationEngine: ObservableObject {
    static let maxHistory = 24

    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var index: Int = -1
    @Published private(set) var currentImage: NSImage?
    @Published private(set) var isBusy = false
    @Published private(set) var statusMessage: String?

    let store: LibraryStore
    let settings: AppSettings

    private var pools: [UUID: [PhotoCandidate]] = [:]
    private var analyses: [String: ImageAnalysis] = [:]
    private var profiles: [UUID: StyleProfile] = [:]
    private var timer: Timer?
    private var bag = Set<AnyCancellable>()

    init(store: LibraryStore, settings: AppSettings) {
        self.store = store
        self.settings = settings

        store.changes
            .sink { [weak self] id in self?.collectionDidChange(id) }
            .store(in: &bag)
        store.$currentCollectionID
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.statusMessage = nil
                    Task { await self.fetchNew() }
                    self.reschedule()
                }
            }
            .store(in: &bag)
        settings.$intervalMinutes.dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.reschedule() } }
            .store(in: &bag)
        settings.$isPaused.dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.reschedule() } }
            .store(in: &bag)
    }

    // MARK: Zustand

    var current: HistoryEntry? { history.indices.contains(index) ? history[index] : nil }

    var counterText: String {
        guard !history.isEmpty else { return "-- / --" }
        return String(format: "%02d / %02d", index + 1, history.count)
    }

    var isCurrentLiked: Bool {
        guard let c = current else { return false }
        return store.isLiked(c.candidate.id, in: store.currentCollectionID)
    }

    /// Zwei bis drei aussagekräftige Begriffe für die Zeile unter dem Namen.
    var tagLine: String {
        if let s = statusMessage { return s }
        let col = store.currentCollection
        if let c = current {
            let weights = profile(for: col).tagWeights
            let picked = StyleEngine.terms(of: c.candidate.tags + (c.analysis?.labels ?? []))
                .filter { $0.count <= 16 }
                .sorted { lhs, rhs in
                    let wl = weights[lhs] ?? 0
                    let wr = weights[rhs] ?? 0
                    return wl == wr ? lhs < rhs : wl > wr
                }
                .prefix(2)
            if !picked.isEmpty { return picked.joined(separator: " · ").uppercased() }
            if let q = c.candidate.query { return q.uppercased() }
        }
        return col.keywords.prefix(2).joined(separator: " · ").uppercased()
    }

    private var interval: TimeInterval { TimeInterval(max(1, settings.intervalMinutes) * 60) }

    // MARK: Ablauf

    func start() {
        loadHistory()
        if current != nil { showEntry(at: index, animated: false) }
        let lastShown = current?.shownAt ?? .distantPast
        if current == nil || (!settings.isPaused && Date().timeIntervalSince(lastShown) >= interval) {
            Task { await fetchNew() }
        }
        reschedule()
    }

    func reschedule() {
        timer?.invalidate()
        timer = nil
        guard !settings.isPaused else { return }
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.fetchNew(automatic: true) }
        }
        t.tolerance = 15
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func togglePause() {
        settings.isPaused.toggle()
    }

    func next() {
        if index < history.count - 1 {
            index += 1
            showEntry(at: index, animated: true)
        } else {
            Task { await fetchNew() }
        }
        reschedule()
    }

    func previous() {
        guard index > 0 else { return }
        index -= 1
        showEntry(at: index, animated: true)
        reschedule()
    }

    func switchCollection(to id: UUID) {
        guard store.collection(id) != nil, id != store.currentCollectionID else { return }
        store.currentCollectionID = id   // löst über den Publisher einen neuen Abruf aus
    }

    func fetchNew(automatic: Bool = false) async {
        guard !isBusy else { return }
        if automatic && settings.isPaused { return }
        isBusy = true
        defer { isBusy = false }

        let colID = store.currentCollectionID
        for _ in 0..<6 {
            guard let cand = await pickCandidate(for: colID) else { break }
            store.markSeen(cand.id, in: colID)
            do {
                let fileName = try await loadDisplay(cand)
                append(HistoryEntry(candidate: cand, collectionID: colID, fileName: fileName,
                                    analysis: analyses[cand.id]))
                statusMessage = nil
                return
            } catch {
                continue   // Bild nicht ladbar – nächster Kandidat
            }
        }
        if statusMessage == nil {
            statusMessage = "Keine neuen Fotos – Suche prüfen"
        }
    }

    // MARK: Likes

    func toggleLike() {
        guard let entry = current else { return }
        let colID = store.currentCollectionID
        if store.isLiked(entry.candidate.id, in: colID) {
            store.removeLike(entry.candidate.id, from: colID, reject: false)
        } else {
            Task { await addLike(entry, to: colID) }
        }
    }

    func addCurrent(to collectionID: UUID) {
        guard let entry = current, !store.isLiked(entry.candidate.id, in: collectionID) else { return }
        Task { await addLike(entry, to: collectionID) }
    }

    private func addLike(_ entry: HistoryEntry, to collectionID: UUID) async {
        let file = Paths.history.appendingPathComponent(entry.fileName)
        let maxPixel = settings.thumbnailMaxPixel
        let quality = settings.thumbnailQuality
        let existing = entry.analysis
        let result = await Task.detached(priority: .userInitiated) { () -> (Data, String, Double, ImageAnalysis?)? in
            guard let img = ImageCodec.downsample(fileURL: file, maxPixel: maxPixel),
                  let encoded = ImageCodec.encodeCompact(img, quality: quality) else { return nil }
            var analysis = existing
            if analysis == nil, let small = ImageCodec.downsample(fileURL: file, maxPixel: 384) {
                analysis = StyleEngine.analyze(small)
            }
            let aspect = Double(img.width) / Double(max(img.height, 1))
            return (encoded.data, encoded.ext, aspect, analysis)
        }.value
        guard let r = result else {
            statusMessage = "Foto konnte nicht gespeichert werden"
            return
        }
        store.addLike(candidate: entry.candidate, analysis: r.3, imageData: r.0, ext: r.1,
                      aspect: r.2, to: collectionID)
        // Sofort neue Vorschläge im gelernten Stil vormerken.
        if collectionID == store.currentCollectionID {
            await refill(collectionID, preferLearned: true)
        }
    }

    // MARK: Lernen

    func profile(for c: PhotoCollection) -> StyleProfile {
        if let p = profiles[c.id] { return p }
        let p = StyleEngine.profile(for: c)
        profiles[c.id] = p
        return p
    }

    /// Likes/Suche geändert (z. B. Foto in der Galerie entfernt): Profil neu berechnen
    /// und vorgemerkte Vorschläge verwerfen, damit neue Vorschläge den aktuellen Stil spiegeln.
    private func collectionDidChange(_ id: UUID) {
        profiles[id] = nil
        pools[id] = nil
        objectWillChange.send()
    }

    // MARK: Vorschläge

    private func pickCandidate(for colID: UUID) async -> PhotoCandidate? {
        if (pools[colID]?.count ?? 0) < 6 { await refill(colID) }
        guard let col = store.collection(colID), let pool = pools[colID], !pool.isEmpty else { return nil }
        let prof = profile(for: col)
        let ranked = pool
            .map { ($0, StyleEngine.prescore($0, profile: prof)) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        var shortlist = Array(ranked.prefix(5))
        if let wildcard = ranked.dropFirst(5).randomElement() { shortlist.append(wildcard) }
        await analyze(shortlist)
        let chosen = StyleEngine.choose(from: shortlist, analyses: analyses, profile: prof, collection: col) ?? shortlist[0]
        pools[colID]?.removeAll { $0.id == chosen.id }
        return chosen
    }

    private func refill(_ colID: UUID, preferLearned: Bool = false) async {
        guard let col = store.collection(colID) else { return }
        let kinds = col.sources.filter { Providers.isUsable($0, for: col) }
        guard !kinds.isEmpty else {
            statusMessage = "Keine Quelle aktiv – Einstellungen prüfen"
            return
        }
        let prof = profile(for: col)
        var fresh: [PhotoCandidate] = []
        var errors: [String] = []

        for attempt in 0..<2 where fresh.isEmpty {
            let queries = StyleEngine.queries(for: col, profile: prof, count: 3, preferLearned: preferLearned && attempt == 0)
            let results = await withTaskGroup(of: (SourceKind, Result<[PhotoCandidate], Error>).self) { group -> [(SourceKind, Result<[PhotoCandidate], Error>)] in
                for kind in kinds {
                    let query = queries.randomElement() ?? col.name
                    let page = attempt == 0 ? Int.random(in: 1...3) : 1
                    group.addTask {
                        do {
                            return (kind, .success(try await Providers.provider(for: kind).search(query: query, collection: col, page: page)))
                        } catch {
                            return (kind, .failure(error))
                        }
                    }
                }
                var out: [(SourceKind, Result<[PhotoCandidate], Error>)] = []
                for await r in group { out.append(r) }
                return out
            }
            let existing = Set((pools[colID] ?? []).map(\.id))
            var seenNow = Set<String>()
            for (kind, r) in results {
                switch r {
                case .success(let list):
                    ConnectionTester.shared.recordSuccess(kind)
                    for c in list where !seenNow.contains(c.id) && !existing.contains(c.id) {
                        seenNow.insert(c.id)
                        if store.hasSeen(c.id, in: colID) || store.isLiked(c.id, in: colID) { continue }
                        if StyleEngine.isExcluded(c, by: col) { continue }
                        fresh.append(c)
                    }
                case .failure(let e):
                    ConnectionTester.shared.recordFailure(kind, e)
                    errors.append("\(kind.shortName): " + ConnectionTester.describe(e, kind))
                }
            }
        }

        if fresh.isEmpty, (pools[colID] ?? []).isEmpty, let first = errors.first {
            statusMessage = first
        }
        pools[colID, default: []].insert(contentsOf: fresh.shuffled(), at: 0)
        if pools[colID]!.count > 200 { pools[colID]!.removeLast(pools[colID]!.count - 200) }
    }

    private func analyze(_ candidates: [PhotoCandidate]) async {
        let missing = candidates.filter { analyses[$0.id] == nil }
        guard !missing.isEmpty else { return }
        let results = await withTaskGroup(of: (String, ImageAnalysis?).self) { group -> [(String, ImageAnalysis?)] in
            for c in missing {
                let id = c.id, url = c.thumbURL
                group.addTask { (id, await InspirationEngine.analyzeRemote(url)) }
            }
            var out: [(String, ImageAnalysis?)] = []
            for await r in group { out.append(r) }
            return out
        }
        for (id, a) in results { if let a { analyses[id] = a } }
        if analyses.count > 600 {
            let keep = Set(pools.values.flatMap { $0.map(\.id) })
            analyses = analyses.filter { keep.contains($0.key) }
        }
    }

    nonisolated static func analyzeRemote(_ url: URL) async -> ImageAnalysis? {
        guard let data = try? await HTTP.get(url, timeout: 15),
              let img = ImageCodec.downsample(data, maxPixel: 384) else { return nil }
        return StyleEngine.analyze(img)
    }

    /// Lädt das Anzeigebild, verkleinert es und legt es im Verlaufs-Cache ab.
    private func loadDisplay(_ c: PhotoCandidate) async throws -> String {
        var urls = [c.imageURL]
        if let f = c.fallbackImageURL, f != c.imageURL { urls.append(f) }
        var lastError: Error = ProviderError.invalidResponse
        for url in urls {
            do {
                let data = try await HTTP.get(url, timeout: 45)
                let name = Paths.safeName(c.id) + "-" + String(UUID().uuidString.prefix(6)) + ".jpg"
                let dest = Paths.history.appendingPathComponent(name)
                let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
                    guard let img = ImageCodec.downsample(data, maxPixel: 1600),
                          min(img.width, img.height) >= 200,
                          let jpeg = ImageCodec.encodeJPEG(img, quality: 0.85) else { return false }
                    return (try? jpeg.write(to: dest, options: .atomic)) != nil
                }.value
                if ok { return name }
                lastError = ProviderError.invalidResponse
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    // MARK: Verlauf

    private func append(_ entry: HistoryEntry) {
        history.append(entry)
        while history.count > Self.maxHistory {
            let old = history.removeFirst()
            try? FileManager.default.removeItem(at: Paths.history.appendingPathComponent(old.fileName))
        }
        index = history.count - 1
        showEntry(at: index, animated: true)
        saveHistory()
    }

    private func showEntry(at i: Int, animated: Bool) {
        guard history.indices.contains(i) else { return }
        let url = Paths.history.appendingPathComponent(history[i].fileName)
        let image = NSImage(contentsOf: url)
        if animated {
            withAnimation(.easeInOut(duration: 0.8)) { currentImage = image }
        } else {
            currentImage = image
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: Paths.historyIndex, options: .atomic)
        }
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: Paths.historyIndex),
              let entries = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        let fm = FileManager.default
        history = entries.filter { fm.fileExists(atPath: Paths.history.appendingPathComponent($0.fileName).path) }
        index = history.count - 1
        // Verwaiste Cache-Dateien aufräumen.
        let valid = Set(history.map(\.fileName))
        if let files = try? fm.contentsOfDirectory(atPath: Paths.history.path) {
            for f in files where !valid.contains(f) {
                try? fm.removeItem(at: Paths.history.appendingPathComponent(f))
            }
        }
    }

    func clearHistoryCache() {
        let keep = current
        let fm = FileManager.default
        for e in history where e.id != keep?.id {
            try? fm.removeItem(at: Paths.history.appendingPathComponent(e.fileName))
        }
        history = keep.map { [$0] } ?? []
        index = history.count - 1
        saveHistory()
    }

    // MARK: Vorschau (nur für das CI-Rendering)

    func injectPreview(entry: HistoryEntry, image: NSImage) {
        history = (0..<24).map { _ in var e = entry; e.id = UUID(); return e }
        index = 2
        currentImage = image
    }
}
