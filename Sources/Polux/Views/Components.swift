import SwiftUI
import AppKit

enum Theme {
    static let cream = Color(red: 0.957, green: 0.953, blue: 0.937)
    static let ink = Color(red: 0.11, green: 0.11, blue: 0.11)
    static let muted = Color(red: 0.50, green: 0.50, blue: 0.48)
    static let heart = Color(red: 0.86, green: 0.15, blue: 0.20)
    static let photoBackground = Color(red: 0.06, green: 0.06, blue: 0.07)
}

/// Schriftzug „polux" – auf dem Polaroid dunkel, in der Galerie weiß auf schwarz.
struct PoluxWordmark: View {
    var size: CGFloat
    var inverted: Bool = false
    var color: Color? = nil

    var body: some View {
        let text = Text("polux")
            .font(.custom("Futura-Bold", size: size))
            .kerning(size * 0.12)
        if inverted {
            text
                .foregroundColor(.white)
                .padding(.horizontal, size * 0.55)
                .padding(.vertical, size * 0.22)
                .background(Color.black)
        } else {
            text.foregroundColor(color ?? Theme.ink.opacity(0.82))
        }
    }
}

/// Zeilenumbrechendes Layout für Schlagwort-Chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        let width = (proposal.width.map { $0.isFinite ? $0 : widest }) ?? widest
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct Chip: View {
    let text: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(text).font(.callout)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.secondary.opacity(0.14)))
    }
}

/// Eingabe für Schlagwörter: Enter oder Komma fügt hinzu, x entfernt.
struct TokenEditor: View {
    let title: String
    @Binding var tokens: [String]
    var placeholder: String

    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            if !tokens.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tokens, id: \.self) { t in
                        Chip(text: t) { tokens.removeAll { $0 == t } }
                    }
                }
            }
            TextField("Hinzufügen", text: $input, prompt: Text(placeholder))
                .textFieldStyle(.roundedBorder)
                .onSubmit(commit)
        }
    }

    private func commit() {
        let parts = input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for p in parts where !p.isEmpty && !tokens.contains(p) { tokens.append(p) }
        input = ""
    }
}

/// Kleiner Speicher für Galerie-Vorschaubilder.
enum ThumbnailCache {
    private static let cache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 150
        return c
    }()

    static func cached(_ url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }

    static func load(_ url: URL) async -> NSImage? {
        if let img = cache.object(forKey: url as NSURL) { return img }
        let img = await Task.detached(priority: .utility) { NSImage(contentsOf: url) }.value
        if let img { cache.setObject(img, forKey: url as NSURL) }
        return img
    }

    static func store(_ image: NSImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
}

/// Einheitlicher Icon-Button im Polaroid.
struct PolaroidIconButton: View {
    let systemName: String
    var size: CGFloat
    var color: Color = Theme.ink
    var help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .regular))
                .foregroundColor(color)
                .frame(width: size * 1.5, height: size * 1.5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
