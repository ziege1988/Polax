import Foundation
import CoreGraphics
import Vision

/// Aus den Likes einer Sammlung abgeleitetes Stilprofil.
struct StyleProfile {
    var tagWeights: [String: Double] = [:]
    var learnedTerms: [String] = []
    var likedPrints: [VNFeaturePrintObservation] = []
    var rejectedPrints: [VNFeaturePrintObservation] = []
    var meanLuminance: Double?
    var likeCount = 0
}

/// Lernt den Bildstil einer Sammlung und bewertet neue Vorschläge.
///
/// Signale:
/// - Schlagwörter/Tags der Quellen + On-Device-Motiverkennung (Vision)
/// - visueller Fingerabdruck (Vision Feature Print) → Ähnlichkeit zu gelikten Bildern
/// - Helligkeit (düstere Inszenierung)
/// - Negativ-Signale aus in der Galerie entfernten Bildern
enum StyleEngine {
    static let stopWords: Set<String> = [
        "photo", "photos", "photograph", "photography", "photographer", "image", "images", "picture",
        "foto", "fotografie", "bild", "the", "and", "with", "for", "from", "this", "that", "flickr",
        "canon", "nikon", "sony", "fujifilm", "fuji", "olympus", "leica", "iphone", "android", "camera",
        "lens", "mm", "untitled", "img", "dsc", "jpg", "jpeg", "raw", "edit", "wikimedia", "commons",
        "pinterest", "unsplash", "pexels", "deviantart", "artstation", "art", "new", "my", "your",
        "free", "stock", "hd", "4k", "wallpaper", "der", "die", "das", "und", "mit"
    ]

    // MARK: Begriffe

    static func normalizeTag(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "#", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func isUsefulTerm(_ t: String) -> Bool {
        t.count >= 3 && t.count <= 24
            && !stopWords.contains(t)
            && t.rangeOfCharacter(from: .decimalDigits) == nil
            && t.rangeOfCharacter(from: .letters) != nil
    }

    static func terms(of tags: [String]) -> Set<String> {
        Set(tags.map(normalizeTag).filter(isUsefulTerm))
    }

    private static func candidateTerms(_ c: PhotoCandidate) -> Set<String> {
        let titleWords = c.title.components(separatedBy: CharacterSet.letters.inverted).filter { $0.count >= 4 }
        return terms(of: c.tags + titleWords)
    }

    /// Gewichte und gelernte Suchbegriffe – leichtgewichtig, ohne Fingerabdrücke.
    static func termProfile(for c: PhotoCollection) -> (weights: [String: Double], learned: [String]) {
        var counts: [String: Int] = [:]
        for like in c.likes {
            for t in terms(of: like.candidate.tags + (like.analysis?.labels ?? [])) {
                counts[t, default: 0] += 1
            }
        }
        let n = Double(max(c.likes.count, 1))
        var weights = counts.mapValues { Double($0) / n }
        for (t, r) in c.rejectedTags {
            weights[t, default: 0] -= min(1.0, 0.25 * r)
        }
        let baseWords = Set(
            (c.keywords + [c.name]).flatMap { normalizeTag($0).split(separator: " ").map(String.init) }
        )
        let excluded = c.excludedWords.map(normalizeTag)
        let minCount = c.likes.count >= 4 ? 2 : 1
        var scored: [(term: String, w: Double)] = []
        for (term, count) in counts {
            guard count >= minCount, !baseWords.contains(term) else { continue }
            let w: Double = weights[term] ?? 0
            guard w > 0 else { continue }
            if excluded.contains(where: { term.contains($0) }) { continue }
            scored.append((term: term, w: w))
        }
        scored.sort { a, b in a.w == b.w ? a.term < b.term : a.w > b.w }
        let learned: [String] = scored.prefix(6).map { $0.term }
        return (weights, learned)
    }

    static func profile(for c: PhotoCollection) -> StyleProfile {
        let tp = termProfile(for: c)
        var p = StyleProfile(tagWeights: tp.weights, learnedTerms: tp.learned)
        p.likedPrints = c.likes.suffix(80).compactMap { $0.analysis?.featurePrint.flatMap(unarchive) }
        p.rejectedPrints = c.rejectedPrints.suffix(40).compactMap(unarchive)
        let lums = c.likes.compactMap { $0.analysis?.luminance }
        p.meanLuminance = lums.isEmpty ? nil : lums.reduce(0, +) / Double(lums.count)
        p.likeCount = c.likes.count
        return p
    }

    // MARK: Suchanfragen

    /// Kombiniert eigene Schlagwörter mit gelernten Stil-Begriffen.
    static func queries(for c: PhotoCollection, profile: StyleProfile, count: Int, preferLearned: Bool = false) -> [String] {
        var base = c.keywords.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if base.isEmpty { base = [c.name] }
        let learnedChance = preferLearned ? 0.85 : 0.5
        var result: [String] = []
        for _ in 0..<(count * 3) where result.count < count {
            var q = base.randomElement()!
            if !profile.learnedTerms.isEmpty, Double.random(in: 0..<1) < learnedChance,
               let t = profile.learnedTerms.prefix(4).randomElement(), !q.lowercased().contains(t) {
                q += " " + t
            }
            if !result.contains(q) { result.append(q) }
        }
        return result.isEmpty ? [base[0]] : result
    }

    // MARK: Bewertung

    static func prescore(_ c: PhotoCandidate, profile: StyleProfile) -> Double {
        let t = candidateTerms(c)
        guard !t.isEmpty, !profile.tagWeights.isEmpty else { return 0 }
        let sum = t.reduce(0.0) { $0 + (profile.tagWeights[$1] ?? 0) }
        return sum / Double(t.count).squareRoot()
    }

    static func isExcluded(_ c: PhotoCandidate, by collection: PhotoCollection) -> Bool {
        let words = collection.excludedWords.map(normalizeTag).filter { !$0.isEmpty }
        guard !words.isEmpty else { return false }
        let hay = normalizeTag(([c.title] + c.tags).joined(separator: " "))
        return words.contains { hay.contains($0) }
    }

    /// Wählt aus einer Vorauswahl das Bild, das am besten zum gelernten Stil passt.
    static func choose(from list: [PhotoCandidate], analyses: [String: ImageAnalysis],
                       profile: StyleProfile, collection: PhotoCollection) -> PhotoCandidate? {
        guard !list.isEmpty else { return nil }
        // Etwas Zufall, damit die Sammlung nicht in einer Stil-Blase festhängt.
        if Double.random(in: 0..<1) < 0.12 { return list.randomElement() }

        let pre = normalized(list.map { prescore($0, profile: profile) })
        let likedSim = closeness(list.map { c in analyses[c.id].flatMap { meanDistance($0, to: profile.likedPrints) } })
        let rejSim = closeness(list.map { c in analyses[c.id].flatMap { meanDistance($0, to: profile.rejectedPrints) } })

        var best: (PhotoCandidate, Double)?
        for (i, c) in list.enumerated() {
            var s = pre[i]
            if let v = likedSim[i] { s += 1.4 * v }
            if let v = rejSim[i] { s -= 0.8 * v }
            if let a = analyses[c.id] {
                s += collection.darkBias * (0.5 - a.luminance) * 1.6
                if let m = profile.meanLuminance { s -= abs(a.luminance - m) * 0.8 }
            } else {
                s -= 0.2
            }
            s += Double.random(in: 0...0.25)
            if best == nil || s > best!.1 { best = (c, s) }
        }
        return best?.0
    }

    private static func normalized(_ values: [Double]) -> [Double] {
        guard let lo = values.min(), let hi = values.max(), hi > lo else { return values.map { _ in 0 } }
        return values.map { ($0 - lo) / (hi - lo) }
    }

    /// Kleinere Distanz → Wert näher an 1 (relativ innerhalb der Vorauswahl).
    private static func closeness(_ distances: [Double?]) -> [Double?] {
        let known = distances.compactMap { $0 }
        guard let lo = known.min(), let hi = known.max() else { return distances }
        return distances.map { d in
            guard let d else { return nil }
            return hi > lo ? (hi - d) / (hi - lo) : 0.5
        }
    }

    private static func meanDistance(_ a: ImageAnalysis, to prints: [VNFeaturePrintObservation]) -> Double? {
        guard !prints.isEmpty, let data = a.featurePrint, let fp = unarchive(data) else { return nil }
        var ds: [Double] = []
        for p in prints {
            var d: Float = 0
            if (try? fp.computeDistance(&d, to: p)) != nil { ds.append(Double(d)) }
        }
        guard !ds.isEmpty else { return nil }
        let nearest = ds.sorted().prefix(3)
        return nearest.reduce(0, +) / Double(nearest.count)
    }

    // MARK: Vision

    static func unarchive(_ data: Data) -> VNFeaturePrintObservation? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }

    /// Analysiert ein (kleines) Bild komplett auf dem Gerät – keine Daten verlassen den Mac.
    static func analyze(_ image: CGImage) -> ImageAnalysis {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let classify = VNClassifyImageRequest()
        let fpRequest = VNGenerateImageFeaturePrintRequest()
        try? handler.perform([classify, fpRequest])

        let labels = (classify.results ?? [])
            .filter { $0.confidence > 0.3 }
            .sorted { $0.confidence > $1.confidence }
            .prefix(8)
            .map { normalizeTag($0.identifier) }

        var printData: Data?
        if let obs = fpRequest.results?.first {
            printData = try? NSKeyedArchiver.archivedData(withRootObject: obs, requiringSecureCoding: true)
        }
        let stats = colorStats(image)
        return ImageAnalysis(labels: Array(labels), featurePrint: printData,
                             luminance: stats.luminance, saturation: stats.saturation)
    }

    static func colorStats(_ image: CGImage) -> (luminance: Double, saturation: Double) {
        let size = 24
        var buffer = [UInt8](repeating: 0, count: size * size * 4)
        let ok: Bool = buffer.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(data: ptr.baseAddress, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard ok else { return (0.5, 0.5) }
        var lum = 0.0, sat = 0.0
        for i in stride(from: 0, to: buffer.count, by: 4) {
            let r = Double(buffer[i]) / 255, g = Double(buffer[i + 1]) / 255, b = Double(buffer[i + 2]) / 255
            lum += 0.2126 * r + 0.7152 * g + 0.0722 * b
            let mx = max(r, g, b), mn = min(r, g, b)
            sat += mx > 0 ? (mx - mn) / mx : 0
        }
        let n = Double(size * size)
        return (lum / n, sat / n)
    }
}
