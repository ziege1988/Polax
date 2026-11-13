import AppKit
import SwiftUI

/// Rendert Polaroid und Galerie mit generierten Beispielbildern als PNG
/// (`Polux --render-preview <ordner>`). Wird in der CI genutzt, um das Layout zu prüfen.
@MainActor
enum PreviewRenderer {
    static var isRendering = false

    static func render(to dir: URL, store: LibraryStore, engine: InspirationEngine,
                       settings: AppSettings, updater: UpdateChecker) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        isRendering = true
        let colID = store.currentCollectionID

        // Beispiel-Likes für die Galerie
        let aspects: [Double] = [0.8, 1.5, 0.67, 1.0, 0.75, 1.33, 0.8, 0.6, 1.2, 0.9]
        for (i, a) in aspects.enumerated() {
            let w = 600, h = Int(600 / a)
            guard let cg = sampleImage(width: w, height: h, seed: i),
                  let enc = ImageCodec.encodeCompact(cg, quality: 0.6) else { continue }
            let cand = sampleCandidate(i)
            store.addLike(candidate: cand, analysis: nil, imageData: enc.data, ext: enc.ext, aspect: a, to: colID)
            if let like = store.collection(colID)?.likes.last {
                ThumbnailCache.store(NSImage(cgImage: cg, size: .zero), for: store.likeFileURL(like, in: colID))
            }
        }

        if let first = store.collection(colID)?.likes.first {
            store.setNote("Licht von links, Schleier, roter Lippenstift", for: first.id, in: colID)
        }
        if let likes = store.collection(colID)?.likes, let col = store.collection(colID) {
            let items: [MoodboardExporter.Item] = likes.compactMap { like in
                guard let img = ThumbnailCache.cached(store.likeFileURL(like, in: colID)) else { return nil }
                return MoodboardExporter.Item(id: like.id, image: img, aspect: like.aspect)
            }
            var credited = likes
            for i in credited.indices {
                credited[i].candidate.author = ["Anna K.", "M. Weber", "", "Jules R."][i % 4]
                credited[i].candidate.license = [nil, "CC BY 2.0", "CC BY-SA 4.0", "Unsplash-Lizenz"][i % 4]
            }
            if let data = MoodboardExporter.render(items: items, credits: MoodboardExporter.credits(for: credited)) {
                try? data.write(to: dir.appendingPathComponent("moodboard.jpg"))
                print("Polux preview: wrote moodboard.jpg (\(col.name))")
            }
        }

        // Aktuelles Polaroid-Foto
        if let cg = sampleImage(width: 800, height: 1000, seed: 42) {
            var cand = sampleCandidate(99)
            cand.origin = "flickr"
            cand.tags = ["dark art", "cinematic"]
            let entry = HistoryEntry(candidate: cand, collectionID: colID, fileName: "preview.jpg", analysis: nil)
            engine.injectPreview(entry: entry, image: NSImage(cgImage: cg, size: .zero))
        }

        let polaroid = PolaroidView()
            .environmentObject(store)
            .environmentObject(engine)
            .environmentObject(settings)
            .environmentObject(updater)
            .background(Color(white: 0.82))
        write(polaroid, to: dir.appendingPathComponent("polaroid.png"))

        let gallery = GalleryView(collectionID: colID, isPreview: true)
            .environmentObject(store)
            .environmentObject(engine)
            .frame(width: 960)
        write(gallery, to: dir.appendingPathComponent("gallery.png"))

        // Einstellungen „Quellen“ mit Beispiel-Status
        let tester = ConnectionTester.shared
        tester.previewOverrides = [
            .openverse: .ok("Verbunden · 20 Testtreffer"),
            .artstation: .failed("ArtStation blockiert die Anfrage gerade (HTTP 403). Später erneut versuchen."),
            .unsplash: .ok("Verbunden · 30 Testtreffer"),
            .flickr: .failed("Flickr: Invalid API Key (Key has invalid format)"),
            .pexels: .missing,
            .deviantart: .unknown
        ]
        let nav = SettingsNavigation.shared
        let pages: [(SettingsPage, CollectionTab, String)] = [
            (.sources, .search, "settings-sources"),
            (.collection(colID), .search, "settings-collection"),
            (.collection(colID), .sources, "settings-collection-sources")
        ]
        for (page, tab, name) in pages {
            nav.collectionTab = tab
            nav.page = page
            let view = SettingsView()
                .environmentObject(store)
                .environmentObject(engine)
                .environmentObject(settings)
                .environmentObject(updater)
            snapshotWindow(view, size: NSSize(width: 960, height: 760), to: dir.appendingPathComponent("\(name).png"))
        }
        let sheet = SourceSetupSheet(kind: .unsplash)
            .environmentObject(store)
            .environmentObject(engine)
        snapshotWindow(sheet, size: NSSize(width: 600, height: 640), to: dir.appendingPathComponent("settings-source-detail.png"))
        store.saveNow()
    }

    /// Rendert über eine echte (unsichtbare) Fensteransicht – nötig für Formulare und Textfelder.
    private static func snapshotWindow<V: View>(_ view: V, size: NSSize, to url: URL) {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        for _ in 0..<5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            hosting.layoutSubtreeIfNeeded()
        }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
            print("Polux preview: wrote \(url.path)")
        }
        window.orderOut(nil)
    }

    private static func write<V: View>(_ view: V, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage, let data = ImageCodec.encodePNG(cg) else {
            print("Polux preview: rendering failed for \(url.lastPathComponent)")
            return
        }
        try? data.write(to: url)
        print("Polux preview: wrote \(url.path) (\(cg.width)x\(cg.height))")
    }

    private static func sampleCandidate(_ i: Int) -> PhotoCandidate {
        let url = URL(string: "https://example.com/\(i).jpg")!
        return PhotoCandidate(id: "preview:\(i)", source: .openverse, origin: ["flickr", "wikimedia", "deviantart", "artstation"][i % 4],
                              title: "Beispiel \(i)", author: "Polux", imageURL: url, fallbackImageURL: nil,
                              thumbURL: url, pageURL: url, tags: ["low key", "portrait", "veil"], query: nil)
    }

    /// Dunkle, „cineastische" Verlaufsbilder als Platzhalter.
    private static func sampleImage(width: Int, height: Int, seed: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let hue = CGFloat((seed * 37) % 100) / 100
        let base = NSColor(hue: hue, saturation: 0.35, brightness: 0.08, alpha: 1).cgColor
        ctx.setFillColor(base)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let light = NSColor(hue: hue, saturation: 0.25, brightness: 0.75, alpha: 1).cgColor
        let clear = NSColor(hue: hue, saturation: 0.25, brightness: 0.75, alpha: 0).cgColor
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [light, clear] as CFArray, locations: [0, 1]) {
            let c = CGPoint(x: CGFloat(width) * (0.35 + 0.1 * CGFloat(seed % 3)), y: CGFloat(height) * 0.6)
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c,
                                   endRadius: CGFloat(min(width, height)) * 0.55, options: [])
        }
        ctx.setFillColor(NSColor(hue: 0.0, saturation: 0.8, brightness: 0.75, alpha: 0.9).cgColor)
        ctx.fillEllipse(in: CGRect(x: CGFloat(width) * 0.42, y: CGFloat(height) * 0.38,
                                   width: CGFloat(width) * 0.06, height: CGFloat(width) * 0.03))
        return ctx.makeImage()
    }
}
