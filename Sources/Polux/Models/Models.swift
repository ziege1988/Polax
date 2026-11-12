import Foundation

/// Bildquellen, aus denen Polux Vorschläge bezieht.
enum SourceKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case openverse
    case unsplash
    case flickr
    case pexels
    case deviantart
    case artstation
    case rss

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openverse: return "Openverse (Flickr, Wikimedia & mehr)"
        case .unsplash: return "Unsplash"
        case .flickr: return "Flickr"
        case .pexels: return "Pexels"
        case .deviantart: return "DeviantArt"
        case .artstation: return "ArtStation (experimentell)"
        case .rss: return "Pinterest-Boards & RSS-Feeds"
        }
    }

    var shortName: String {
        switch self {
        case .openverse: return "openverse"
        case .unsplash: return "unsplash"
        case .flickr: return "flickr"
        case .pexels: return "pexels"
        case .deviantart: return "deviantart"
        case .artstation: return "artstation"
        case .rss: return "pinterest"
        }
    }

    /// Quellen, die einen (kostenlosen) API-Schlüssel benötigen.
    var needsCredentials: Bool {
        switch self {
        case .unsplash, .flickr, .pexels, .deviantart: return true
        default: return false
        }
    }
}

/// Ein Bildvorschlag aus dem Netz.
struct PhotoCandidate: Codable, Hashable, Identifiable {
    var id: String
    var source: SourceKind
    /// Herkunft für das Etikett im Polaroid (z. B. „flickr", „wikimedia").
    var origin: String
    var title: String
    var author: String
    /// Bild für die Anzeige (mittlere bis große Auflösung).
    var imageURL: URL
    /// Alternative, falls `imageURL` nicht lädt.
    var fallbackImageURL: URL?
    /// Kleines Vorschaubild für die Stil-Analyse.
    var thumbURL: URL
    /// Originalseite (Linkansicht).
    var pageURL: URL?
    var tags: [String]
    var query: String?
}

/// Ergebnis der On-Device-Bildanalyse (Apple Vision).
struct ImageAnalysis: Codable, Hashable {
    /// Erkannte Motiv-Labels (VNClassifyImageRequest).
    var labels: [String]
    /// Archivierter VNFeaturePrintObservation – Fingerabdruck für Ähnlichkeit.
    var featurePrint: Data?
    /// Mittlere Helligkeit 0…1 (niedrig = düster).
    var luminance: Double
    /// Mittlere Sättigung 0…1.
    var saturation: Double
}

/// Ein gelikter, lokal gespeicherter Eintrag einer Sammlung.
struct LikedPhoto: Codable, Hashable, Identifiable {
    var id: String
    var candidate: PhotoCandidate
    var analysis: ImageAnalysis?
    var likedAt: Date
    /// Dateiname des platzsparenden Vorschaubilds (HEIC/JPEG).
    var fileName: String
    /// Seitenverhältnis Breite/Höhe.
    var aspect: Double
    /// Größe der gespeicherten Datei in Bytes.
    var bytes: Int
}

/// Eine Sammlung mit Suchprofil, Likes und gelerntem Stil.
struct PhotoCollection: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var keywords: [String]
    var excludedWords: [String]
    var sources: Set<SourceKind>
    var allowNudity: Bool
    /// 0 = egal, 1 = stark düstere / Low-Key-Bildsprache bevorzugen.
    var darkBias: Double
    var photosOnly: Bool
    /// Pinterest-Board- oder sonstige RSS-Feed-URLs.
    var feeds: [String]
    var likes: [LikedPhoto]
    /// Negativ-Signale aus entfernten Fotos.
    var rejectedTags: [String: Double]
    var rejectedPrints: [Data]
    /// Bereits gezeigte Bilder (begrenzt), um Wiederholungen zu vermeiden.
    var seenIDs: [String]

    init(id: UUID = UUID(),
         name: String,
         keywords: [String] = [],
         excludedWords: [String] = [],
         sources: Set<SourceKind> = Set(SourceKind.allCases),
         allowNudity: Bool = true,
         darkBias: Double = 0.3,
         photosOnly: Bool = true,
         feeds: [String] = []) {
        self.id = id
        self.name = name
        self.keywords = keywords
        self.excludedWords = excludedWords
        self.sources = sources
        self.allowNudity = allowNudity
        self.darkBias = darkBias
        self.photosOnly = photosOnly
        self.feeds = feeds
        self.likes = []
        self.rejectedTags = [:]
        self.rejectedPrints = []
        self.seenIDs = []
    }

    enum CodingKeys: String, CodingKey {
        case id, name, keywords, excludedWords, sources, allowNudity, darkBias, photosOnly, feeds
        case likes, rejectedTags, rejectedPrints, seenIDs
    }

    // Tolerantes Dekodieren, damit spätere Versionen neue Felder ergänzen können.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Sammlung"
        keywords = try c.decodeIfPresent([String].self, forKey: .keywords) ?? []
        excludedWords = try c.decodeIfPresent([String].self, forKey: .excludedWords) ?? []
        let rawSources = try c.decodeIfPresent([String].self, forKey: .sources) ?? SourceKind.allCases.map(\.rawValue)
        sources = Set(rawSources.compactMap(SourceKind.init(rawValue:)))
        allowNudity = try c.decodeIfPresent(Bool.self, forKey: .allowNudity) ?? true
        darkBias = try c.decodeIfPresent(Double.self, forKey: .darkBias) ?? 0.3
        photosOnly = try c.decodeIfPresent(Bool.self, forKey: .photosOnly) ?? true
        feeds = try c.decodeIfPresent([String].self, forKey: .feeds) ?? []
        likes = try c.decodeIfPresent([LikedPhoto].self, forKey: .likes) ?? []
        rejectedTags = try c.decodeIfPresent([String: Double].self, forKey: .rejectedTags) ?? [:]
        rejectedPrints = try c.decodeIfPresent([Data].self, forKey: .rejectedPrints) ?? []
        seenIDs = try c.decodeIfPresent([String].self, forKey: .seenIDs) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(keywords, forKey: .keywords)
        try c.encode(excludedWords, forKey: .excludedWords)
        try c.encode(sources.map(\.rawValue).sorted(), forKey: .sources)
        try c.encode(allowNudity, forKey: .allowNudity)
        try c.encode(darkBias, forKey: .darkBias)
        try c.encode(photosOnly, forKey: .photosOnly)
        try c.encode(feeds, forKey: .feeds)
        try c.encode(likes, forKey: .likes)
        try c.encode(rejectedTags, forKey: .rejectedTags)
        try c.encode(rejectedPrints, forKey: .rejectedPrints)
        try c.encode(seenIDs, forKey: .seenIDs)
    }

    /// Alles, was die Suche beeinflusst – ändert sich das, werden Vorschläge neu geholt.
    var searchSignature: String {
        [keywords.joined(separator: "|"),
         excludedWords.joined(separator: "|"),
         sources.map(\.rawValue).sorted().joined(separator: ","),
         "\(allowNudity)", String(format: "%.2f", darkBias), "\(photosOnly)",
         feeds.joined(separator: "|")].joined(separator: "#")
    }

    var totalBytes: Int { likes.reduce(0) { $0 + $1.bytes } }

    static func starter() -> PhotoCollection {
        PhotoCollection(
            name: "Dark Art",
            keywords: ["dark fine art portrait", "low key portrait", "cinematic portrait",
                       "veil portrait", "fine art nude", "chiaroscuro photography"],
            allowNudity: true,
            darkBias: 0.7,
            photosOnly: true
        )
    }
}

enum WidgetLevel: String, CaseIterable, Identifiable {
    case desktop, normal, floating
    var id: String { rawValue }
    var label: String {
        switch self {
        case .desktop: return "Auf dem Schreibtisch (wie ein Widget)"
        case .normal: return "Normal zwischen Fenstern"
        case .floating: return "Immer im Vordergrund"
        }
    }
}

enum PolaroidSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var width: CGFloat {
        switch self {
        case .small: return 270
        case .medium: return 330
        case .large: return 410
        }
    }
    var label: String {
        switch self {
        case .small: return "Klein"
        case .medium: return "Mittel"
        case .large: return "Groß"
        }
    }
}

enum ProviderError: LocalizedError {
    case missingCredentials(SourceKind)
    case http(Int, String)
    case api(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingCredentials(let k): return "\(k.displayName): API-Schlüssel fehlt"
        case .http(let code, let host): return "\(host) antwortet mit HTTP \(code)"
        case .api(let msg): return msg
        case .invalidResponse: return "Ungültige Antwort"
        }
    }
}
