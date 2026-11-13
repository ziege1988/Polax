import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Exportiert ausgewählte Lieblingsfotos als Moodboard-Mosaik (JPEG)
/// mit „polux“-Schriftzug und kleingedruckter Urheber-/Lizenz-Fußnote.
@MainActor
enum MoodboardExporter {
    struct Item: Identifiable {
        let id: String
        let image: NSImage
        let aspect: Double
    }

    static func export(_ likes: [LikedPhoto], collection: PhotoCollection, store: LibraryStore) {
        let items: [Item] = likes.compactMap { like in
            guard let img = NSImage(contentsOf: store.likeFileURL(like, in: collection.id)) else { return nil }
            return Item(id: like.id, image: img, aspect: like.aspect)
        }
        guard !items.isEmpty else { return }
        guard let data = render(items: items, credits: credits(for: likes)) else {
            let alert = NSAlert()
            alert.messageText = "Moodboard konnte nicht erstellt werden."
            alert.runModal()
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg]
        panel.canCreateDirectories = true
        let date = Date().formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
        panel.nameFieldStringValue = "Moodboard \(collection.name) \(date).jpg"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    static func render(items: [Item], credits: String) -> Data? {
        let renderer = ImageRenderer(content: MoodboardView(items: items, credits: credits))
        renderer.scale = 1.5
        guard let cg = renderer.cgImage else { return nil }
        return ImageCodec.encodeJPEG(cg, quality: 0.88)
    }

    /// „Fotos: Name (CC BY 2.0) · Name (©) …“ – ohne Links und Plattformnamen.
    static func credits(for likes: [LikedPhoto]) -> String {
        var seen = Set<String>()
        var parts: [String] = []
        for like in likes {
            let author = like.candidate.author.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = author.isEmpty ? "Urheber unbekannt" : author
            let license = like.candidate.license ?? "©"
            let entry = "\(name) (\(license))"
            if seen.insert(entry).inserted { parts.append(entry) }
        }
        return "Fotos: " + parts.joined(separator: " · ") + ". Nur zur Inspiration – Rechte liegen bei den jeweiligen Urheber:innen."
    }
}

/// Layout des Moodboards: schwarzer Balken mit Schriftzug, Mosaik, Fußnote.
struct MoodboardView: View {
    let items: [MoodboardExporter.Item]
    let credits: String

    private var columns: Int {
        switch items.count {
        case 0...2: return items.count == 1 ? 1 : 2
        case 3...6: return 3
        default: return 4
        }
    }

    var body: some View {
        let width: CGFloat = 1500
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                PoluxWordmark(size: 58, color: .white)
                Spacer()
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 30)
            .frame(width: width)
            .background(Color.black)

            MasonryGrid(items: items, columns: columns, spacing: 14, aspect: { $0.aspect }) { item in
                Color.black.opacity(0.06)
                    .aspectRatio(item.aspect, contentMode: .fit)
                    .overlay(
                        Image(nsImage: item.image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    )
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            .padding(48)

            Text(credits)
                .font(.system(size: 8))
                .foregroundColor(Color.black.opacity(0.35))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 48)
                .padding(.bottom, 24)
        }
        .frame(width: width)
        .background(Theme.cream)
        .environment(\.colorScheme, .light)
    }
}
