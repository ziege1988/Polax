import Foundation
import Combine
import SwiftUI

/// Verwaltet Sammlungen, Likes und deren Dateien.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var collections: [PhotoCollection]
    @Published var currentCollectionID: UUID {
        didSet { UserDefaults.standard.set(currentCollectionID.uuidString, forKey: "currentCollectionID") }
    }

    /// Meldet Änderungen, die Suche oder Stilprofil einer Sammlung betreffen.
    let changes = PassthroughSubject<UUID, Never>()

    private var seenSets: [UUID: Set<String>] = [:]
    private var saveWork: DispatchWorkItem?
    private static let maxSeen = 4000
    private static let maxRejectedPrints = 40

    private struct LibraryFile: Codable {
        var version: Int
        var collections: [PhotoCollection]
    }

    init() {
        Paths.ensureDirectories()
        var loaded: [PhotoCollection] = []
        if let data = try? Data(contentsOf: Paths.library),
           let file = try? JSONDecoder().decode(LibraryFile.self, from: data) {
            loaded = file.collections
        }
        if loaded.isEmpty { loaded = [PhotoCollection.starter()] }
        collections = loaded
        let stored = UserDefaults.standard.string(forKey: "currentCollectionID").flatMap(UUID.init(uuidString:))
        currentCollectionID = loaded.first(where: { $0.id == stored })?.id ?? loaded[0].id
    }

    // MARK: Zugriff

    var currentCollection: PhotoCollection {
        collection(currentCollectionID) ?? collections[0]
    }

    func collection(_ id: UUID) -> PhotoCollection? {
        collections.first { $0.id == id }
    }

    func isLiked(_ photoID: String, in collectionID: UUID) -> Bool {
        collection(collectionID)?.likes.contains { $0.id == photoID } ?? false
    }

    func hasSeen(_ photoID: String, in collectionID: UUID) -> Bool {
        if seenSets[collectionID] == nil {
            seenSets[collectionID] = Set(collection(collectionID)?.seenIDs ?? [])
        }
        return seenSets[collectionID]?.contains(photoID) ?? false
    }

    func likeFileURL(_ like: LikedPhoto, in collectionID: UUID) -> URL {
        Paths.likes(collectionID).appendingPathComponent(like.fileName)
    }

    var totalLikeBytes: Int64 { Int64(collections.reduce(0) { $0 + $1.totalBytes }) }

    // MARK: Sammlungen

    @discardableResult
    func addCollection(name: String) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Neue Sammlung" : trimmed
        let c = PhotoCollection(name: finalName, keywords: [finalName])
        collections.append(c)
        scheduleSave()
        return c.id
    }

    func deleteCollection(_ id: UUID) {
        guard collections.count > 1, let idx = collections.firstIndex(where: { $0.id == id }) else { return }
        collections.remove(at: idx)
        try? FileManager.default.removeItem(at: Paths.likes(id))
        seenSets[id] = nil
        if currentCollectionID == id { currentCollectionID = collections[0].id }
        scheduleSave()
    }

    func moveCollections(from source: IndexSet, to destination: Int) {
        collections.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    /// Übernimmt eine bearbeitete Sammlung. Suchrelevante Änderungen werden gemeldet.
    func update(_ collection: PhotoCollection) {
        guard let idx = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        let old = collections[idx]
        guard old != collection else { return }
        collections[idx] = collection
        scheduleSave()
        if old.searchSignature != collection.searchSignature { changes.send(collection.id) }
    }

    func mutate(_ id: UUID, notify: Bool = true, _ body: (inout PhotoCollection) -> Void) {
        guard let idx = collections.firstIndex(where: { $0.id == id }) else { return }
        body(&collections[idx])
        scheduleSave()
        if notify { changes.send(id) }
    }

    // MARK: Likes

    func addLike(candidate: PhotoCandidate, analysis: ImageAnalysis?, imageData: Data,
                 ext: String, aspect: Double, to collectionID: UUID) {
        let dir = Paths.likes(collectionID)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileName = Paths.safeName(candidate.id) + "." + ext
        do {
            try imageData.write(to: dir.appendingPathComponent(fileName), options: .atomic)
        } catch {
            NSLog("Polux: Like konnte nicht gespeichert werden: \(error)")
            return
        }
        let like = LikedPhoto(id: candidate.id, candidate: candidate, analysis: analysis, likedAt: Date(),
                              fileName: fileName, aspect: max(0.2, min(5, aspect)), bytes: imageData.count)
        mutate(collectionID) { c in
            c.likes.removeAll { $0.id == like.id }
            c.likes.append(like)
        }
    }

    /// Entfernt ein Like. Mit `reject` merkt sich die Sammlung den Stil als „nicht gewünscht".
    func removeLike(_ photoID: String, from collectionID: UUID, reject: Bool) {
        guard let c = collection(collectionID), let like = c.likes.first(where: { $0.id == photoID }) else { return }
        try? FileManager.default.removeItem(at: likeFileURL(like, in: collectionID))
        mutate(collectionID) { c in
            c.likes.removeAll { $0.id == photoID }
            guard reject else { return }
            let terms = StyleEngine.terms(of: like.candidate.tags + (like.analysis?.labels ?? []))
            for t in terms { c.rejectedTags[t, default: 0] += 1 }
            if let fp = like.analysis?.featurePrint {
                c.rejectedPrints.append(fp)
                if c.rejectedPrints.count > Self.maxRejectedPrints {
                    c.rejectedPrints.removeFirst(c.rejectedPrints.count - Self.maxRejectedPrints)
                }
            }
        }
    }

    /// Notiz zu einem Lieblingsfoto speichern (leer = löschen).
    func setNote(_ note: String, for photoID: String, in collectionID: UUID) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        mutate(collectionID, notify: false) { c in
            guard let i = c.likes.firstIndex(where: { $0.id == photoID }) else { return }
            c.likes[i].note = trimmed.isEmpty ? nil : trimmed
        }
    }

    func resetRejections(_ collectionID: UUID) {
        mutate(collectionID) { c in
            c.rejectedTags = [:]
            c.rejectedPrints = []
        }
    }

    func markSeen(_ photoID: String, in collectionID: UUID) {
        guard !hasSeen(photoID, in: collectionID) else { return }
        seenSets[collectionID, default: []].insert(photoID)
        mutate(collectionID, notify: false) { c in
            c.seenIDs.append(photoID)
            if c.seenIDs.count > Self.maxSeen {
                let drop = c.seenIDs.prefix(c.seenIDs.count - Self.maxSeen)
                c.seenIDs.removeFirst(drop.count)
                self.seenSets[collectionID]?.subtract(drop)
            }
        }
    }

    // MARK: Persistenz

    func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.saveNow() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        let file = LibraryFile(version: 1, collections: collections)
        do {
            let data = try JSONEncoder().encode(file)
            try data.write(to: Paths.library, options: .atomic)
        } catch {
            NSLog("Polux: Speichern fehlgeschlagen: \(error)")
        }
    }
}
