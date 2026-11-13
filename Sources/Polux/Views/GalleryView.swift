import SwiftUI
import AppKit

/// Mosaik-Galerie einer Sammlung – mit Moodboard-Auswahl, Notizen und „Mehr davon“.
struct GalleryView: View {
    let collectionID: UUID
    var isPreview = false

    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var engine: InspirationEngine

    @State private var detail: LikedPhoto?
    @State private var selecting = false
    @State private var selection = Set<String>()

    private var collection: PhotoCollection? { store.collection(collectionID) }

    private var likes: [LikedPhoto] {
        (collection?.likes ?? []).sorted { $0.likedAt > $1.likedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !likes.isEmpty {
                toolbar
                if isPreview {
                    grid(likes, width: 900).padding(20)
                } else {
                    GeometryReader { geo in
                        ScrollView {
                            grid(likes, width: geo.size.width - 40)
                                .padding(20)
                        }
                    }
                }
            } else {
                emptyState
            }
        }
        .frame(minWidth: 620, minHeight: 440)
        .background(Theme.cream)
        .environment(\.colorScheme, .light)
        .sheet(item: $detail) { like in
            PhotoDetailView(likeID: like.id, collectionID: collectionID, close: { detail = nil })
                .environmentObject(store)
                .environmentObject(engine)
        }
    }

    // MARK: Kopf

    private var header: some View {
        let c = collection
        let learned = c.map { StyleEngine.termProfile(for: $0).learned } ?? []
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                PoluxWordmark(size: 46, color: .white)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, isPreview ? 18 : 34)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity)
            .background(Color.black)

            VStack(alignment: .leading, spacing: 6) {
                Text(c?.name ?? "Sammlung")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(Theme.ink)
                Text("\(c?.likes.count ?? 0) Fotos · \(Paths.formatBytes(Int64(c?.totalBytes ?? 0))) lokal")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.muted)
                if !learned.isEmpty {
                    Text("Gelernter Stil: " + learned.prefix(5).joined(separator: " · "))
                        .font(.system(size: 12))
                        .kerning(0.4)
                        .foregroundColor(Theme.muted)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 4)
        }
    }

    // MARK: Werkzeugleiste (Moodboard)

    private var toolbar: some View {
        HStack(spacing: 10) {
            if selecting {
                Text(selection.isEmpty ? "Fotos für das Moodboard antippen" : "\(selection.count) ausgewählt")
                    .font(.callout)
                    .foregroundColor(Theme.muted)
                Spacer()
                Button(selection.count == likes.count ? "Keine" : "Alle") {
                    selection = selection.count == likes.count ? [] : Set(likes.map(\.id))
                }
                Button("Abbrechen") {
                    selecting = false
                    selection = []
                }
                Button {
                    exportMoodboard()
                } label: {
                    Label("Als Bild exportieren", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .tint(.black)
                .disabled(selection.isEmpty)
            } else {
                Spacer()
                Button {
                    selecting = true
                } label: {
                    Label("Moodboard erstellen", systemImage: "square.grid.3x2")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.black))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Fotos auswählen und als Moodboard-Bild exportieren")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private func exportMoodboard() {
        guard let c = collection else { return }
        let chosen = likes.filter { selection.contains($0.id) }
        MoodboardExporter.export(chosen, collection: c, store: store)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "heart")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(Theme.muted)
            Text("Noch keine Lieblingsfotos")
                .font(.system(size: 16, weight: .medium))
            Text("Tippe im Polaroid auf das Herz, um ein Foto in diese Sammlung zu übernehmen.\nPolux lernt daraus den Stil für neue Vorschläge.")
                .font(.system(size: 13))
                .foregroundColor(Theme.muted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func grid(_ likes: [LikedPhoto], width: CGFloat) -> some View {
        let columns = max(2, min(6, Int(width / 220)))
        return MasonryGrid(items: likes, columns: columns, spacing: 12, aspect: { $0.aspect }) { like in
            GalleryTile(
                like: like,
                fileURL: store.likeFileURL(like, in: collectionID),
                selecting: selecting,
                selected: selection.contains(like.id),
                onTap: {
                    if selecting {
                        if selection.contains(like.id) { selection.remove(like.id) } else { selection.insert(like.id) }
                    } else {
                        detail = like
                    }
                },
                onMore: { engine.moreLike(like, in: collectionID) },
                onRemove: { remove(like) }
            )
        }
    }

    private func remove(_ like: LikedPhoto) {
        selection.remove(like.id)
        withAnimation(.easeInOut(duration: 0.25)) {
            store.removeLike(like.id, from: collectionID, reject: true)
        }
    }
}

/// Verteilt Elemente nach Höhe auf Spalten (Pinterest-artiges Mosaik).
struct MasonryGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let columns: Int
    let spacing: CGFloat
    let aspect: (Item) -> Double
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        let cols = distribute()
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<cols.count, id: \.self) { i in
                VStack(spacing: spacing) {
                    ForEach(cols[i]) { item in content(item) }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func distribute() -> [[Item]] {
        var cols = Array(repeating: [Item](), count: max(1, columns))
        var heights = Array(repeating: 0.0, count: cols.count)
        for item in items {
            let i = heights.indices.min(by: { heights[$0] < heights[$1] }) ?? 0
            cols[i].append(item)
            heights[i] += 1.0 / max(0.2, aspect(item))
        }
        return cols
    }
}

/// Kleiner gelber Zettel als Hinweis auf eine Notiz.
struct PostItBadge: View {
    var note: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 1.0, green: 0.88, blue: 0.35))
                .frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.35), radius: 2, x: 1, y: 2)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(Color.black.opacity(0.35))
                        .frame(width: i == 2 ? 9 : 15, height: 1.5)
                }
            }
            .padding(.top, 7)
            .padding(.leading, 5)
        }
        .rotationEffect(.degrees(6))
        .help(note)
    }
}

struct GalleryTile: View {
    let like: LikedPhoto
    let fileURL: URL
    var selecting: Bool
    var selected: Bool
    var onTap: () -> Void
    var onMore: () -> Void
    var onRemove: () -> Void

    @State private var image: NSImage?
    @State private var hovering = false

    var body: some View {
        Color.black.opacity(0.07)
            .aspectRatio(like.aspect, contentMode: .fit)
            .overlay {
                if let img = image ?? ThumbnailCache.cached(fileURL) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .opacity(selecting && !selected ? 0.55 : 1)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.black, lineWidth: selecting && selected ? 3 : 0)
            )
            .overlay(alignment: .topLeading) {
                if selecting {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.white, selected ? Color.black : Color.black.opacity(0.35))
                        .padding(8)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let note = like.note, !note.isEmpty {
                    PostItBadge(note: note).padding(6)
                }
            }
            .overlay(alignment: .bottom) {
                if hovering && !selecting {
                    HStack(spacing: 12) {
                        Text(like.candidate.origin)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        tileButton("wand.and.stars", help: "Mehr davon im Polaroid") { onMore() }
                        tileButton("arrow.up.forward.square", help: "Originalquelle öffnen") {
                            NSWorkspace.shared.open(like.candidate.pageURL ?? like.candidate.imageURL)
                        }
                        tileButton("trash", help: "Aus Sammlung entfernen") { onRemove() }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onHover { h in withAnimation(.easeInOut(duration: 0.15)) { hovering = h } }
            .onTapGesture { onTap() }
            .contextMenu {
                Button("Ansehen & Notiz") { onTap() }
                Button("Mehr davon im Polaroid") { onMore() }
                Button("Originalquelle öffnen") {
                    NSWorkspace.shared.open(like.candidate.pageURL ?? like.candidate.imageURL)
                }
                Button("Link kopieren") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString((like.candidate.pageURL ?? like.candidate.imageURL).absoluteString,
                                                   forType: .string)
                }
                Divider()
                Button("Aus Sammlung entfernen", role: .destructive) { onRemove() }
            }
            .task(id: fileURL) { image = await ThumbnailCache.load(fileURL) }
    }

    private func tileButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Großansicht: Foto, Notiz, Farbpalette und Licht-Einschätzung.
struct PhotoDetailView: View {
    let likeID: String
    let collectionID: UUID
    var close: () -> Void

    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var engine: InspirationEngine
    @State private var fullImage: NSImage?
    @State private var thumb: NSImage?
    @State private var note = ""
    @State private var look: LookAnalysis?

    private var like: LikedPhoto? {
        store.collection(collectionID)?.likes.first { $0.id == likeID }
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color.black
                if let img = fullImage ?? thumb {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                }
                if fullImage == nil {
                    ProgressView().controlSize(.small).colorScheme(.dark)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            sidebar
                .frame(width: 290)
                .background(Theme.cream)
        }
        .frame(width: 1020, height: 700)
        .environment(\.colorScheme, .light)
        .task { await load() }
        .onDisappear { saveNote() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let like {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(like.candidate.title.isEmpty ? "Ohne Titel" : like.candidate.title)
                                .font(.headline)
                                .lineLimit(3)
                            Text(like.candidate.author.isEmpty ? "Urheber unbekannt" : like.candidate.author)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Notiz
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            PostItBadge(note: "").scaleEffect(0.6).frame(width: 18, height: 18)
                            Text("Notiz").font(.subheadline.weight(.semibold))
                        }
                        TextEditor(text: $note)
                            .font(.callout)
                            .frame(height: 110)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 1.0, green: 0.96, blue: 0.75)))
                        Text("z. B. Licht, Styling, Pose, Location")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Look
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Look").font(.subheadline.weight(.semibold))
                        if let look {
                            HStack(spacing: 0) {
                                ForEach(look.palette) { s in
                                    Rectangle()
                                        .fill(Color(nsColor: s.color))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 34)
                                        .help(s.hex)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            HStack(spacing: 0) {
                                ForEach(look.palette) { s in
                                    Text(s.hex)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity)
                                        .textSelection(.enabled)
                                }
                            }
                            FlowLayout(spacing: 6) {
                                ForEach(look.summary, id: \.self) { Chip(text: $0) }
                            }
                            Text("Automatische Einschätzung aus Helligkeit, Kontrast und Farben.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }

                    if let like {
                        let terms = Array(StyleEngine.terms(of: like.candidate.tags + (like.analysis?.labels ?? []))).sorted().prefix(10)
                        if !terms.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Stichworte").font(.subheadline.weight(.semibold))
                                Text(terms.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(18)
            }

            Divider()
            VStack(spacing: 8) {
                HStack {
                    Button {
                        if let like { engine.moreLike(like, in: collectionID) }
                        close()
                    } label: {
                        Label("Mehr davon", systemImage: "wand.and.stars")
                    }
                    Spacer()
                    Button("Quelle") {
                        if let like { NSWorkspace.shared.open(like.candidate.pageURL ?? like.candidate.imageURL) }
                    }
                }
                HStack {
                    Button("Entfernen", role: .destructive) {
                        store.removeLike(likeID, from: collectionID, reject: true)
                        close()
                    }
                    Spacer()
                    Button("Fertig") {
                        saveNote()
                        close()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
        }
    }

    private func saveNote() {
        guard like != nil, note != (like?.note ?? "") else { return }
        store.setNote(note, for: likeID, in: collectionID)
    }

    private func load() async {
        guard let like else { return }
        note = like.note ?? ""
        let fileURL = store.likeFileURL(like, in: collectionID)
        thumb = await ThumbnailCache.load(fileURL)
        look = await Task.detached(priority: .userInitiated) { () -> LookAnalysis? in
            guard let cg = ImageCodec.downsample(fileURL: fileURL, maxPixel: 300) else { return nil }
            return LookAnalyzer.analyze(cg)
        }.value
        for url in [like.candidate.imageURL, like.candidate.fallbackImageURL].compactMap({ $0 }) {
            if let data = try? await HTTP.get(url, timeout: 45),
               let cg = await Task.detached(priority: .userInitiated, operation: { ImageCodec.downsample(data, maxPixel: 2200) }).value {
                fullImage = NSImage(cgImage: cg, size: .zero)
                break
            }
        }
    }
}
