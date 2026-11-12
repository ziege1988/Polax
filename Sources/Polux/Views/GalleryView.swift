import SwiftUI
import AppKit

/// Mosaik-Galerie einer Sammlung.
struct GalleryView: View {
    let collectionID: UUID
    var isPreview = false

    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var engine: InspirationEngine

    @State private var detail: LikedPhoto?

    private var collection: PhotoCollection? { store.collection(collectionID) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let c = collection, !c.likes.isEmpty {
                let likes = c.likes.sorted { $0.likedAt > $1.likedAt }
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
        .frame(minWidth: 560, minHeight: 420)
        .background(Theme.cream)
        .environment(\.colorScheme, .light)
        .sheet(item: $detail) { like in
            PhotoDetailView(like: like, collectionID: collectionID, close: { detail = nil })
                .environmentObject(store)
        }
    }

    private var header: some View {
        let c = collection
        let learned = c.map { StyleEngine.termProfile(for: $0).learned } ?? []
        return VStack(alignment: .leading, spacing: 0) {
            // Schwarzer Balken über die gesamte Breite mit großem Schriftzug links
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
                onOpen: { detail = like },
                onRemove: { remove(like) }
            )
        }
    }

    private func remove(_ like: LikedPhoto) {
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

struct GalleryTile: View {
    let like: LikedPhoto
    let fileURL: URL
    var onOpen: () -> Void
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
            .overlay(alignment: .bottom) {
                if hovering {
                    HStack(spacing: 10) {
                        Text(like.candidate.origin)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
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
            .onTapGesture { onOpen() }
            .contextMenu {
                Button("Ansehen") { onOpen() }
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

/// Großansicht eines gelikten Fotos – lädt die Originalgröße nur bei Bedarf aus dem Netz.
struct PhotoDetailView: View {
    let like: LikedPhoto
    let collectionID: UUID
    var close: () -> Void

    @EnvironmentObject var store: LibraryStore
    @State private var fullImage: NSImage?
    @State private var thumb: NSImage?

    var body: some View {
        VStack(spacing: 0) {
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
            .frame(minHeight: 420)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(like.candidate.title.isEmpty ? "Ohne Titel" : like.candidate.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text([like.candidate.author, like.candidate.origin].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    let terms = Array(StyleEngine.terms(of: like.candidate.tags + (like.analysis?.labels ?? []))).sorted().prefix(10)
                    if !terms.isEmpty {
                        Text(terms.joined(separator: " · "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Button("Quelle öffnen") {
                    NSWorkspace.shared.open(like.candidate.pageURL ?? like.candidate.imageURL)
                }
                Button("Entfernen", role: .destructive) {
                    store.removeLike(like.id, from: collectionID, reject: true)
                    close()
                }
                Button("Schließen", action: close).keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .frame(width: 820, height: 680)
        .task {
            thumb = await ThumbnailCache.load(store.likeFileURL(like, in: collectionID))
            for url in [like.candidate.imageURL, like.candidate.fallbackImageURL].compactMap({ $0 }) {
                if let data = try? await HTTP.get(url, timeout: 45),
                   let cg = await Task.detached(priority: .userInitiated, operation: { ImageCodec.downsample(data, maxPixel: 2200) }).value {
                    fullImage = NSImage(cgImage: cg, size: .zero)
                    break
                }
            }
        }
    }
}
