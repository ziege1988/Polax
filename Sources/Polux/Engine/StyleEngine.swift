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
/// Verständliche Gründe für das Filterprotokoll.
enum FilterReason {
    static let keyword = "Schlagwort passt nicht"
    static let excludedWord = "Ausschlusswort"
    static let painting = "Gemälde / Zeichnung"
    static let digitalArt = "Gemalte Digitalkunst"
    static let anime = "Anime / Comic"
    static let stillLife = "Stillleben / Abstrakt"
    static let place = "Architektur / Landschaft ohne Person"
    static let wrongSubject = "Falsche Person (Frau/Mann)"
    static let noPerson = "Keine Person erkannt"
    static let animeVision = "Cartoon/Anime (Bilderkennung)"
    static let paintingVision = "Gemälde (Bilderkennung)"
    static let nonPhoto = "Text, Plakat oder Streifenformat"
    static let duplicate = "Doppelt"
    static let seen = "Schon gezeigt"
    static let tooSmall = "Bild nicht ladbar / zu klein"
}

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
        let subjectWords = SubjectFocus.female.positiveWords.union(SubjectFocus.male.positiveWords).union(SubjectFocus.couple.positiveWords)
        let excluded = c.excludedWords.map(normalizeTag)
        let minCount = c.likes.count >= 4 ? 2 : 1
        var scored: [(term: String, w: Double)] = []
        for (term, count) in counts {
            guard count >= minCount, !baseWords.contains(term), !subjectWords.contains(term) else { continue }
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
    /// Suchanfragen bestehen nur aus den eigenen Schlagwörtern (plus ggf. „woman/man/couple“ aus „Person im Bild“).
    /// Gelernte Stilbegriffe beeinflussen nur noch die Reihenfolge, nicht die Suche selbst.
    static func queries(for c: PhotoCollection, profile: StyleProfile, count: Int) -> [String] {
        var base = c.keywords.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if base.isEmpty { base = [c.name] }
        var result: [String] = []
        for kw in base.shuffled() where result.count < count {
            var q = kw
            if let term = c.subject.searchTerm, !words(of: q).contains(where: c.subject.positiveWords.contains) {
                q += " " + term
            }
            if !result.contains(q) { result.append(q) }
        }
        return result.isEmpty ? [base[0]] : result
    }

    // MARK: Schlagwort-Treffer (unscharf)

    /// Bedeutungstragende Wörter eines Schlagworts.
    static func keywordTokens(_ keyword: String) -> [String] {
        let fill: Set<String> = ["the", "and", "with", "for", "of", "in", "a", "an", "und", "mit", "der", "die", "das"]
        return Array(words(of: keyword)).filter { $0.count >= 3 && !fill.contains($0) }
    }

    /// Zwei Wörter gelten als gleich bei Plural/Wortstamm („goth“ ~ „gothic“) oder einem Tippfehler.
    static func fuzzyEqual(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let short = a.count <= b.count ? a : b, long = a.count <= b.count ? b : a
        if short.count >= 4 && long.hasPrefix(short) { return true }
        if short.count >= 5 && long.count - short.count <= 1 && levenshtein(a, b) <= 1 { return true }
        return false
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        var prev = Array(0...y.count)
        for i in 1...max(x.count, 1) where !x.isEmpty {
            var cur = [i] + Array(repeating: 0, count: y.count)
            for j in 1...max(y.count, 1) where !y.isEmpty {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[y.count]
    }

    /// Allgemeine Wörter, die fast überall vorkommen – sie zählen nur halb und reichen allein nicht.
    static let genericTokens: Set<String> = [
        "dark", "black", "white", "light", "fine", "art", "arts", "photo", "photography", "image", "beautiful",
        "model", "woman", "women", "man", "men", "girl", "people", "person", "style", "mood", "moody",
        "color", "colour", "night", "shoot", "shooting", "studio", "foto", "fotografie", "schön", "frau", "mann"
    ]

    /// Wie gut passt ein Bild zu einem Schlagwort? Liefert Wert 0…1 und das beste Schlagwort.
    static func bestKeyword(_ c: PhotoCandidate, analysis: ImageAnalysis?, collection: PhotoCollection) -> (score: Double, keyword: String?) {
        let keywords = collection.keywords.filter { !keywordTokens($0).isEmpty }
        guard !keywords.isEmpty else { return (1, nil) }
        var hay = candidateWords(c)
        for l in analysis?.labels ?? [] { hay.formUnion(words(of: l)) }
        guard !hay.isEmpty else { return (0, nil) }
        var best: (Double, String?) = (0, nil)
        for kw in keywords {
            let toks = keywordTokens(kw)
            let specific = toks.filter { !genericTokens.contains($0) }
            var total = 0.0, got = 0.0, specificHit = false
            for t in toks {
                let w = genericTokens.contains(t) ? 0.5 : 1.0
                total += w
                if hay.contains(where: { fuzzyEqual(t, $0) }) {
                    got += w
                    if w == 1.0 { specificHit = true }
                }
            }
            // Hat das Schlagwort prägende Wörter, muss mindestens eines davon vorkommen.
            var score = total > 0 ? got / total : 0
            if !specific.isEmpty && !specificHit { score = min(score, 0.2) }
            if score > best.0 { best = (score, kw) }
        }
        return best
    }

    static func keywordMatch(_ c: PhotoCandidate, analysis: ImageAnalysis?, collection: PhotoCollection) -> Double {
        bestKeyword(c, analysis: analysis, collection: collection).score
    }

    /// Mindestanteil – bei „editorial gothic“ genügt ein Treffer, bei vier Wörtern zwei.
    static let keywordThreshold = 0.5

    /// Ausschlusswörter: Einzelwörter als ganzes Wort (unscharf), Wortgruppen als Phrase. Prüft auch Motiv-Labels.
    static func matchesExcludedWords(_ c: PhotoCandidate, analysis: ImageAnalysis?, collection: PhotoCollection) -> Bool {
        let entries = collection.excludedWords.map(normalizeTag).filter { !$0.isEmpty }
        guard !entries.isEmpty else { return false }
        var hay = candidateWords(c)
        for l in analysis?.labels ?? [] { hay.formUnion(words(of: l)) }
        let text = normalizeTag(([c.title] + c.tags + (analysis?.labels ?? [])).joined(separator: " "))
        for e in entries {
            let toks = Array(words(of: e))
            if toks.count > 1 {
                if text.contains(e) { return true }
            } else if let t = toks.first {
                if t.count <= 3 ? hay.contains(t) || hay.contains(t + "s") : hay.contains(where: { fuzzyEqual(t, $0) }) {
                    return true
                }
            }
        }
        return false
    }

    // MARK: Bewertung

    static func prescore(_ c: PhotoCandidate, profile: StyleProfile) -> Double {
        let t = candidateTerms(c)
        guard !t.isEmpty, !profile.tagWeights.isEmpty else { return 0 }
        let sum = t.reduce(0.0) { $0 + (profile.tagWeights[$1] ?? 0) }
        return sum / Double(t.count).squareRoot()
    }

    // MARK: Was nicht vorgeschlagen wird
    //
    // Erlaubt: Fotos sowie Digitalkunst/KI-Bilder mit Personen.
    // Aussortiert: klassische Gemälde & Zeichnungen, Anime/Comic, Stillleben und Abstraktes.

    /// Klassische Malerei und Zeichnung (Titel/Tags). Bewusst ohne Fotografie-Fachbegriffe
    /// wie „Rembrandt-Licht“, „Caravaggio“, „baroque“ und ohne „digital art“/„concept art“.
    static let paintingWords: Set<String> = [
        "oilpainting", "acrylic", "watercolor", "watercolour", "aquarelle", "gouache", "tempera",
        "canvas", "fresco", "mural", "lithograph", "etching", "engraving", "woodcut", "inkdrawing",
        "graphite", "charcoaldrawing", "sketchbook",
        "gemälde", "malerei", "ölgemälde", "aquarell", "zeichnung", "leinwand",
        "peinture", "pintura", "dipinto",
        // Abfotografierte Kunstwerke / Alte Meister / Museen
        "altarpiece", "triptych", "diptych", "polyptych", "retable", "retablo", "iconography",
        "bosch", "hieronymus", "bruegel", "brueghel", "dürer", "durer", "botticelli", "titian", "tizian",
        "museum", "museo", "musée", "musee", "louvre", "prado", "uffizi", "rijksmuseum", "mauritshuis",
        "kunsthistorisches", "hermitage",
        "painter", "maler"
    ]

    /// Gemalte/gezeichnete Digitalkunst & Illustration (auch KI). Ausnahme: Titel/Tags betonen Fotorealismus.
    static let digitalArtWords: Set<String> = [
        "illustration", "illustrations", "illustrated", "painting", "paintings",
        "drawing", "drawings", "drawn", "sketch", "digitalpainting", "digitalillustration", "digitalart",
        "conceptart", "characterdesign", "characterart", "fantasyart", "artnouveau", "arcimboldo", "mucha",
        "klimt", "pinup", "vector", "stylized", "stylised", "lineart", "celshading", "artstation",
        "artwork", "artworks", "procreate", "photoshoppainting", "speedpaint",
        "portraitart", "popart", "psychedelic", "kunstwerk"
    ]

    /// Digitalkunst-Phrasen – gesperrt, außer Titel/Tags betonen Fotorealismus.
    static let digitalArtPhrases: [String] = [
        "art nouveau", "digital art", "digital painting", "concept art", "fantasy art", "character design",
        "pin up", "pin-up", "trending on artstation", "digital illustration"
    ]

    /// Begriffe, die für ein fotorealistisches (auch KI-generiertes) Bild sprechen.
    static let photorealWords: Set<String> = [
        "photorealistic", "photoreal", "photorealism", "hyperrealistic", "hyperrealism", "realistic",
        "photograph", "photography", "photo", "dslr", "mm", "filmgrain", "raw", "canon", "nikon", "sony",
        "fujifilm", "leica", "bokeh", "lightroom", "fotografie"
    ]

    /// Anime, Comic & Cartoon.
    static let animeWords: Set<String> = [
        "anime", "manga", "cartoon", "cartoons", "comic", "comics", "chibi", "kawaii", "waifu", "husbando",
        "hentai", "ecchi", "vtuber", "toon", "pixar", "fanart", "otaku"
    ]

    /// Vision-Motiv-Labels, die auf Menschen hindeuten, auch ohne erkanntes Gesicht.
    static let personLabels: Set<String> = [
        "people", "person", "adult", "woman", "man", "child", "wedding", "bride", "groom", "hand", "hands",
        "finger", "portrait", "selfie", "tattoo", "skin", "dance", "couple"
    ]

    /// Wörter, die auf Menschen im Bild hindeuten.
    static let peopleWords: Set<String> = [
        "portrait", "portraits", "people", "person", "model", "models", "woman", "women", "man", "men",
        "girl", "boy", "lady", "couple", "nude", "body", "face", "figure", "dancer", "bride", "selfie",
        "fashion", "boudoir", "porträt", "frau", "mann", "akt", "modell",
        "wedding", "bridal", "groom", "engagement", "elopement", "kiss", "kissing", "lovers", "hands", "rings",
        "tattoo", "tattoos", "tattooed", "makeup", "bodypaint", "nudeart", "artnude", "finearts",
        "hochzeit", "braut", "bräutigam", "brautpaar", "paar", "hände", "verlobung"
    ]

    /// Motive ohne Menschen (Architektur, Landschaft, Stadt) – nur relevant, wenn Personen verlangt sind
    /// und Titel/Tags keinen Hinweis auf Menschen enthalten.
    static let placeWords: Set<String> = [
        "architecture", "building", "buildings", "facade", "palace", "castle", "church", "cathedral",
        "monument", "landmark", "statue", "sculpture", "skyline", "cityscape", "city", "street", "bridge",
        "landscape", "nature", "forest", "mountain", "mountains", "sea", "beach", "sunset", "sky", "clouds",
        "interior", "ruins", "arch", "tower", "museum", "night", "lights", "illumination", "car", "cars",
        "architektur", "gebäude", "kirche", "schloss", "landschaft", "stadt"
    ]

    /// Stillleben, Produkte und Abstraktes.
    static let stillLifeWords: Set<String> = [
        "stilllife", "stillleben", "abstract", "abstraction", "abstrakt", "fractal", "mandala",
        "geometric", "flatlay", "product", "products", "food"
    ]

    static let excludedPhrases: [String] = [
        "oil on canvas", "oil painting", "acrylic on", "on canvas", "oil on panel", "pen and ink",
        "pencil drawing", "charcoal drawing", "still life", "flat lay", "product photography",
        "food photography", "abstract art", "anime style", "anime girl", "manga style", "cartoon style",
        "national gallery", "old master", "alte meister", "art institute", "public domain art",
        "15th century", "16th century", "17th century", "oil paint", "pop art",
        "vision of tondal", "last judgment", "garden of earthly"
    ]

    /// Vision-Kennungen für Gemälde/Zeichnung – greift bei allen Quellen außer Digitalkunst (ArtStation).
    static let paintIdentifiers: Set<String> = {
        let keys = ["painting", "drawing", "sketch", "watercolor", "fresco", "mural", "canvas", "illustration"]
        let all = (try? VNClassifyImageRequest().supportedIdentifiers()) ?? []
        let found = all.filter { id in keys.contains { id.lowercased().contains($0) } }
        return Set(found.isEmpty ? ["painting", "drawing"] : found)
    }()

    static let paintThreshold = 0.28

    /// Bilderkennung: wirkt das Bild gemalt/gezeichnet statt fotografiert? Gilt für alle Quellen –
    /// erlaubt sind nur Fotos und fotorealistische (KI-)Bilder.
    static func looksLikeClassicPainting(_ c: PhotoCandidate, _ a: ImageAnalysis?) -> Bool {
        guard let a else { return false }
        if let score = a.paintScore {
            // Sehr sicher → raus. Mittlere Sicherheit nur bei bunten, „glatten“ Bildern
            // (dunkle, entsättigte Bodypaint-Akte werden sonst fälschlich als Malerei erkannt).
            if score >= 0.5 { return true }
            if score >= paintThreshold && a.saturation > 0.42 { return true }
        }
        // Extrem gesättigte, „glatte“ Bilder sind fast immer digitale Malerei, kaum Fotos.
        if a.saturation > 0.62 { return true }
        return false
    }

    /// Vision-Kennungen für Cartoon/Anime/Comic – zur Laufzeit aus der Taxonomie ermittelt.
    /// (Gemalt wirkende Digitalkunst mit Personen bleibt erlaubt.)
    static let artIdentifiers: Set<String> = {
        let keys = ["cartoon", "anime", "comic"]
        let all = (try? VNClassifyImageRequest().supportedIdentifiers()) ?? []
        let found = all.filter { id in keys.contains { id.lowercased().contains($0) } }
        return Set(found.isEmpty ? ["cartoon"] : found)
    }()

    /// Ab diesem Vision-Wert gilt ein Bild als Cartoon/Anime.
    static let artThreshold = 0.3

    /// Prüft Titel/Tags auf Gemälde, Anime, Stillleben oder Abstraktes.
    static func looksLikePainting(_ c: PhotoCandidate) -> Bool { artReason(c) != nil }

    /// Grund, warum Titel/Tags auf Kunst statt Foto hindeuten (nil = unauffällig).
    static func artReason(_ c: PhotoCandidate) -> String? {
        let w = words(of: ([c.title] + c.tags).joined(separator: " "))
        let text = ([c.title] + c.tags).joined(separator: " ").lowercased()
        if !w.isDisjoint(with: animeWords) { return FilterReason.anime }
        if !w.isDisjoint(with: stillLifeWords) { return FilterReason.stillLife }
        if !w.isDisjoint(with: paintingWords) { return FilterReason.painting }
        // Digitale Malerei: nur erlaubt, wenn ausdrücklich fotorealistisch beschrieben.
        if w.isDisjoint(with: photorealWords) {
            if !w.isDisjoint(with: digitalArtWords) { return FilterReason.digitalArt }
            if digitalArtPhrases.contains(where: { text.contains($0) }) { return FilterReason.digitalArt }
        }
        if excludedPhrases.contains(where: { text.contains($0) }) { return FilterReason.painting }
        return nil
    }

    /// Bilderkennung: wirkt das Bild wie Cartoon/Anime?
    static func looksLikePainting(_ a: ImageAnalysis?) -> Bool {
        guard let score = a?.artScore else { return false }
        return score >= artThreshold
    }

    /// Plakate, Screenshots, Memes, Collagen-Banner: viel Text oder extremes Format.
    static func looksLikeNonPhoto(_ a: ImageAnalysis?) -> Bool {
        guard let a else { return false }
        if let t = a.textCoverage, t > 0.05 { return true }
        if let r = a.aspect, r > 2.1 || r < 0.42 { return true }
        return false
    }

    /// Ohne erkannte Person, obwohl die Sammlung Personen verlangt (Stillleben, Landschaft, Abstraktes)?
    static func lacksPeople(_ a: ImageAnalysis?, collection: PhotoCollection, candidate: PhotoCandidate? = nil) -> Bool {
        guard collection.requirePeople || collection.subject != .any else { return false }
        // Experimentelle Akte (Unschärfe, Doppelbelichtung, Verfremdung) erkennt die Bilderkennung oft nicht
        // als Person – sagen Titel/Tags eindeutig „nude“, „model“, „body“ …, gilt das als Person.
        if let c = candidate, !candidateWords(c).isDisjoint(with: peopleWords) { return false }
        guard let a, let n = a.personCount else { return true }   // nicht prüfbar → lieber aussortieren
        if n > 0 { return false }
        // Detailaufnahmen ohne Gesicht/Körper (Hände mit Ringen, Anstecker) zählen über die Motiv-Labels.
        return Set(a.labels).isDisjoint(with: personLabels)
    }

    /// Einzelwörter (klein geschrieben) – für Motiv-Erkennung über ganze Wörter.
    static func words(of text: String) -> Set<String> {
        Set(text.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty })
    }

    private static func candidateWords(_ c: PhotoCandidate) -> Set<String> {
        words(of: ([c.title] + c.tags).joined(separator: " "))
    }

    static func isExcluded(_ c: PhotoCandidate, by collection: PhotoCollection) -> Bool {
        exclusionReason(c, collection: collection) != nil
    }

    /// Prüfung anhand von Titel/Tags (vor dem Laden des Bildes). Liefert den Grund oder nil.
    static func exclusionReason(_ c: PhotoCandidate, collection: PhotoCollection) -> String? {
        if let r = artReason(c) { return r }
        if collection.requirePeople || collection.subject != .any {
            let w = candidateWords(c)
            if w.isDisjoint(with: peopleWords) && !w.isDisjoint(with: placeWords) { return FilterReason.place }
        }
        // Motiv: z. B. bei „Frau“ Fotos verwerfen, die klar als Mann beschrieben sind (und umgekehrt).
        let negatives = collection.subject.negativeWords
        if !negatives.isEmpty {
            let w = candidateWords(c)
            if !w.isDisjoint(with: negatives) && w.isDisjoint(with: collection.subject.positiveWords) {
                return FilterReason.wrongSubject
            }
        }
        if matchesExcludedWords(c, analysis: nil, collection: collection) { return FilterReason.excludedWord }
        // Nur Treffer zu den eigenen Schlagwörtern (Pinterest-Boards sind selbst kuratiert und ausgenommen).
        if c.source != .rss, !collection.keywords.isEmpty,
           keywordMatch(c, analysis: nil, collection: collection) < keywordThreshold {
            return FilterReason.keyword
        }
        return nil
    }

    /// Prüfung nach der Bildanalyse. Liefert den Grund oder nil.
    static func imageReason(_ c: PhotoCandidate, analysis a: ImageAnalysis?, collection: PhotoCollection) -> String? {
        if looksLikePainting(a) { return FilterReason.animeVision }
        if looksLikeNonPhoto(a) { return FilterReason.nonPhoto }
        if c.source != .rss, !collection.keywords.isEmpty,
           keywordMatch(c, analysis: a, collection: collection) < keywordThreshold { return FilterReason.keyword }
        if matchesExcludedWords(c, analysis: a, collection: collection) { return FilterReason.excludedWord }
        if looksLikeClassicPainting(c, a) { return FilterReason.paintingVision }
        if lacksPeople(a, collection: collection, candidate: c) { return FilterReason.noPerson }
        return nil
    }

    /// Bonus, wenn ein Kandidat ausdrücklich zum gewünschten Motiv passt.
    static func subjectBonus(_ c: PhotoCandidate, collection: PhotoCollection) -> Double {
        let positives = collection.subject.positiveWords
        guard !positives.isEmpty else { return 0 }
        return candidateWords(c).isDisjoint(with: positives) ? 0 : 0.5
    }

    /// Wählt aus einer Vorauswahl das Bild, das am besten zum gelernten Stil passt.
    static func choose(from list: [PhotoCandidate], analyses: [String: ImageAnalysis],
                       profile: StyleProfile, collection: PhotoCollection) -> PhotoCandidate? {
        guard !list.isEmpty else { return nil }
        // Motiv-Prüfung am Bild: Bei Frau/Mann/Paar Fotos ohne erkannte Person aussortieren.
        var list = list
        if collection.subject != .any || collection.requirePeople {
            let withPeople = list.filter { c in !lacksPeople(analyses[c.id], collection: collection, candidate: c) }
            if !withPeople.isEmpty { list = withPeople }
        }
        // Etwas Zufall, damit die Sammlung nicht in einer Stil-Blase festhängt.
        // (Früher: 12 % rein zufällige Auswahl „gegen die Stil-Blase“ – entfernt, das brachte kuriose Fotos.)

        let pre = normalized(list.map { prescore($0, profile: profile) })
        let likedSim = closeness(list.map { c in analyses[c.id].flatMap { meanDistance($0, to: profile.likedPrints) } })
        let rejSim = closeness(list.map { c in analyses[c.id].flatMap { meanDistance($0, to: profile.rejectedPrints) } })

        var best: (PhotoCandidate, Double)?
        for (i, c) in list.enumerated() {
            var s = pre[i] + subjectBonus(c, collection: collection)
            s += 2.5 * keywordMatch(c, analysis: analyses[c.id], collection: collection)
            if let n = analyses[c.id]?.personCount {
                switch collection.subject {
                case .female, .male: s += n == 1 ? 0.4 : (n > 2 ? -0.4 : 0)
                case .couple: s += n == 2 ? 0.6 : -0.3
                case .any: break
                }
            }
            if let v = likedSim[i] { s += 1.4 * v }
            if let v = rejSim[i] { s -= 0.8 * v }
            if let a = analyses[c.id] {
                s -= max(0, a.saturation - 0.45) * 2.0   // sehr bunte Bilder wirken selten fotografisch
                if let p = a.paintScore { s -= p * (a.saturation > 0.42 ? 1.5 : 0.6) }
                s += collection.darkBias * (0.5 - a.luminance) * 1.6
                if let m = profile.meanLuminance { s -= abs(a.luminance - m) * 0.8 }
            } else {
                s -= 0.2
            }
            s += Double.random(in: 0...0.04)   // nur minimale Abwechslung bei Gleichstand
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
        let humans = VNDetectHumanRectanglesRequest()
        humans.upperBodyOnly = false
        let faces = VNDetectFaceRectanglesRequest()
        let text = VNDetectTextRectanglesRequest()
        try? handler.perform([classify, fpRequest, humans, faces, text])
        let textCoverage = (text.results ?? []).reduce(0.0) { $0 + Double($1.boundingBox.width * $1.boundingBox.height) }
        // Nur deutlich sichtbare Personen zählen – kleine Figuren (Statuen, Passanten in der Ferne) nicht.
        let humanCount = (humans.results ?? [])
            .filter { $0.confidence > 0.4 && $0.boundingBox.height >= 0.22 }.count
        let faceCount = (faces.results ?? [])
            .filter { $0.confidence > 0.5 && $0.boundingBox.height >= 0.06 }.count

        let artScore = (classify.results ?? [])
            .filter { artIdentifiers.contains($0.identifier) }
            .map { Double($0.confidence) }
            .max() ?? 0
        let paintScore = (classify.results ?? [])
            .filter { paintIdentifiers.contains($0.identifier) }
            .map { Double($0.confidence) }
            .max() ?? 0
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
                             luminance: stats.luminance, saturation: stats.saturation,
                             personCount: max(humanCount, faceCount), dhash: dhash(image),
                             artScore: artScore, paintScore: paintScore,
                             textCoverage: min(1, textCoverage),
                             aspect: Double(image.width) / Double(max(image.height, 1)))
    }

    /// Differenz-Hash: 9×8 Graustufen, je Zeile Nachbarn vergleichen → 64 Bit.
    /// Erkennt dasselbe Bild auch in anderer Größe oder Kompression.
    static func dhash(_ image: CGImage) -> UInt64? {
        let w = 9, h = 8
        var buffer = [UInt8](repeating: 0, count: w * h)
        let ok: Bool = buffer.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        var hash: UInt64 = 0
        var bit: UInt64 = 0
        for y in 0..<h {
            for x in 0..<(w - 1) {
                if buffer[y * w + x] > buffer[y * w + x + 1] { hash |= (1 << bit) }
                bit += 1
            }
        }
        return hash
    }

    static func isNearDuplicate(_ a: UInt64, _ b: UInt64) -> Bool {
        (a ^ b).nonzeroBitCount <= 6
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
