import Foundation

protocol ImageProvider {
    var kind: SourceKind { get }
    func search(query: String, collection: PhotoCollection, page: Int) async throws -> [PhotoCandidate]
}

enum Providers {
    static func provider(for kind: SourceKind) -> ImageProvider {
        switch kind {
        case .openverse: return OpenverseProvider()
        case .unsplash: return UnsplashProvider()
        case .flickr: return FlickrProvider()
        case .pexels: return PexelsProvider()
        case .deviantart: return DeviantArtProvider()
        case .artstation: return ArtStationProvider()
        case .rss: return RSSProvider()
        }
    }

    /// Ob eine Quelle für diese Sammlung nutzbar ist (Schlüssel bzw. Feeds vorhanden).
    static func isUsable(_ kind: SourceKind, for collection: PhotoCollection) -> Bool {
        switch kind {
        case .openverse, .artstation: return true
        case .unsplash: return Keychain.has(.unsplash)
        case .flickr: return Keychain.has(.flickr)
        case .pexels: return Keychain.has(.pexels)
        case .deviantart: return Keychain.has(.deviantartID) && Keychain.has(.deviantartSecret)
        case .rss: return !collection.feeds.isEmpty
        }
    }

    static func hasCredentials(_ kind: SourceKind) -> Bool {
        switch kind {
        case .unsplash: return Keychain.has(.unsplash)
        case .flickr: return Keychain.has(.flickr)
        case .pexels: return Keychain.has(.pexels)
        case .deviantart: return Keychain.has(.deviantartID) && Keychain.has(.deviantartSecret)
        default: return true
        }
    }
}

// MARK: - Openverse (ohne Schlüssel; bündelt u. a. Flickr, Wikimedia Commons, Museen)

struct OpenverseProvider: ImageProvider {
    let kind = SourceKind.openverse

    private struct Response: Decodable { let results: [Item] }
    private struct Item: Decodable {
        let id: String
        let title: String?
        let url: String?
        let thumbnail: String?
        let foreign_landing_url: String?
        let creator: String?
        let source: String?
        let provider: String?
        let tags: [Tag]?
    }
    private struct Tag: Decodable { let name: String }

    func search(query: String, collection: PhotoCollection, page: Int) async throws -> [PhotoCandidate] {
        var comps = URLComponents(string: "https://api.openverse.org/v1/images/")!
        var items: [URLQueryItem] = [
            .init(name: "q", value: query),
            .init(name: "page_size", value: "20"),
            .init(name: "page", value: String(page))
        ]
        if collection.allowNudity { items.append(.init(name: "mature", value: "true")) }
        if collection.photosOnly { items.append(.init(name: "category", value: "photograph")) }
        comps.queryItems = items
        let resp = try await HTTP.json(Response.self, comps.url!)
        return resp.results.compactMap { r in
            guard let img = HTTP.secureURL(r.url) else { return nil }
            let thumb = HTTP.secureURL(r.thumbnail) ?? img
            return PhotoCandidate(
                id: "openverse:\(r.id)", source: .openverse,
                origin: (r.source ?? r.provider ?? "openverse").replacingOccurrences(of: "_", with: " "),
                title: r.title ?? "", author: r.creator ?? "",
                imageURL: img, fallbackImageURL: thumb, thumbURL: thumb,
                pageURL: HTTP.secureURL(r.foreign_landing_url),
                tags: (r.tags ?? []).map(\.name), query: query)
        }
    }
}

// MARK: - Unsplash

struct UnsplashProvider: ImageProvider {
    let kind = SourceKind.unsplash

    private struct Response: Decodable { let results: [Item] }
    private struct Item: Decodable {
        let id: String
        let description: String?
        let alt_description: String?
        let urls: URLs
        let links: Links
        let user: User
        let tags: [Tag]?
    }
    private struct URLs: Decodable { let regular: String; let small: String }
    private struct Links: Decodable { let html: String }
    private struct User: Decodable { let name: String? }
    private struct Tag: Decodable { let title: String? }

    func search(query: String, collection: PhotoCollection, page: Int) async throws -> [PhotoCandidate] {
        guard let key = Keychain.get(.unsplash) else { throw ProviderError.missingCredentials(kind) }
        var comps = URLComponents(string: "https://api.unsplash.com/search/photos")!
        comps.queryItems = [
            .init(name: "query", value: query),
            .init(name: "per_page", value: "30"),
            .init(name: "page", value: String(page)),
            .init(name: "content_filter", value: collection.allowNudity ? "low" : "high")
        ]
        let resp = try await HTTP.json(Response.self, comps.url!,
                                       headers: ["Authorization": "Client-ID \(key)", "Accept-Version": "v1"])
        return resp.results.compactMap { r in
            guard let img = HTTP.secureURL(r.urls.regular), let thumb = HTTP.secureURL(r.urls.small) else { return nil }
            return PhotoCandidate(
                id: "unsplash:\(r.id)", source: .unsplash, origin: "unsplash",
                title: r.description ?? r.alt_description ?? "", author: r.user.name ?? "",
                imageURL: img, fallbackImageURL: thumb, thumbURL: thumb,
                pageURL: HTTP.secureURL(r.links.html),
                tags: (r.tags ?? []).compactMap(\.title) + [r.alt_description ?? ""].filter { !$0.isEmpty },
                query: query)
        }
    }
}

// MARK: - Flickr

struct FlickrProvider: ImageProvider {
    let kind = SourceKind.flickr

    private struct Response: Decodable {
        let stat: String
        let message: String?
        let photos: Photos?
    }
    private struct Photos: Decodable { let photo: [Item] }
    private struct Item: Decodable {
        let id: String
        let owner: String
        let title: String?
        let ownername: String?
        let tags: String?
        let url_l: String?
        let url_c: String?
        let url_z: String?
        let url_q: String?
    }

    func search(query: String, collection: PhotoCollection, page: Int) async throws -> [PhotoCandidate] {
        guard let key = Keychain.get(.flickr) else { throw ProviderError.missingCredentials(kind) }
        var comps = URLComponents(string: "https://api.flickr.com/services/rest/")!
        comps.queryItems = [
            .init(name: "method", value: "flickr.photos.search"),
            .init(name: "api_key", value: key),
            .init(name: "text", value: query),
            .init(name: "sort", value: "interestingness-desc"),
            .init(name: "media", value: "photos"),
            .init(name: "content_types", value: "0"),
            // 3 = eingeschränkte Inhalte zulassen (greift bei anonymen API-Abfragen nur eingeschränkt)
            .init(name: "safe_search", value: collection.allowNudity ? "3" : "1"),
            .init(name: "extras", value: "url_l,url_c,url_z,url_q,tags,owner_name"),
            .init(name: "per_page", value: "30"),
            .init(name: "page", value: String(page)),
            .init(name: "format", value: "json"),
            .init(name: "nojsoncallback", value: "1")
        ]
        let resp = try await HTTP.json(Response.self, comps.url!)
        guard resp.stat == "ok", let photos = resp.photos else {
            throw ProviderError.api("Flickr: \(resp.message ?? "Fehler")")
        }
        return photos.photo.compactMap { r in
            guard let img = HTTP.secureURL(r.url_l ?? r.url_c ?? r.url_z) else { return nil }
            let thumb = HTTP.secureURL(r.url_q ?? r.url_z) ?? img
            return PhotoCandidate(
                id: "flickr:\(r.id)", source: .flickr, origin: "flickr",
                title: r.title ?? "", author: r.ownername ?? "",
                imageURL: img, fallbackImageURL: HTTP.secureURL(r.url_z), thumbURL: thumb,
                pageURL: URL(string: "https://www.flickr.com/photos/\(r.owner)/\(r.id)"),
                tags: (r.tags ?? "").split(separator: " ").map(String.init), query: query)
        }
    }
}

// MARK: - Pexels

struct PexelsProvider: ImageProvider {
    let kind = SourceKind.pexels

    private struct Response: Decodable { let photos: [Item] }
    private struct Item: Decodable {
        let id: Int
        let url: String
        let photographer: String?
        let alt: String?
        let src: Src
    }
    private struct Src: Decodable { let large: String; let medium: String }

    func search(query: String, collection: PhotoCollection, page: Int) async throws -> [PhotoCandidate] {
        guard let key = Keychain.get(.pexels) else { throw ProviderError.missingCredentials(kind) }
        var comps = URLComponents(string: "https://api.pexels.com/v1/search")!
        comps.queryItems = [
            .init(name: "query", value: query),
            .init(name: "per_page", value: "30"),
            .init(name: "page", value: String(page))
        ]
        let resp = try await HTTP.json(Response.self, comps.url!, headers: ["Authorization": key])
        return resp.photos.compactMap { r in
            guard let img = HTTP.secureURL(r.src.large), let thumb = HTTP.secureURL(r.src.medium) else { return nil }
            let alt = r.alt ?? ""
            return PhotoCandidate(
                id: "pexels:\(r.id)", source: .pexels, origin: "pexels",
                title: alt, author: r.photographer ?? "",
                imageURL: img, fallbackImageURL: thumb, thumbURL: thumb,
                pageURL: HTTP.secureURL(r.url),
                tags: alt.split(separator: " ").map(String.init), query: query)
        }
    }
}

// MARK: - DeviantArt (OAuth Client Credentials)

actor DeviantArtAuth {
    static let shared = DeviantArtAuth()
    private var token: String?
    private var expiry = Date.distantPast

    private struct TokenResponse: Decodable {
        let access_token: String?
        let expires_in: Double?
        let error_description: String?
    }

    func reset() {
        token = nil
        expiry = .distantPast
    }

    func accessToken() async throws -> String {
        if let t = token, Date() < expiry { return t }
        guard let id = Keychain.get(.deviantartID), let secret = Keychain.get(.deviantartSecret) else {
            throw ProviderError.missingCredentials(.deviantart)
        }
        var req = URLRequest(url: URL(string: "https://www.deviantart.com/oauth2/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            .init(name: "grant_type", value: "client_credentials"),
            .init(name: "client_id", value: id),
            .init(name: "client_secret", value: secret)
        ]
        req.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let data = try await HTTP.data(req)
        let resp = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let t = resp.access_token else {
            throw ProviderError.api("DeviantArt: \(resp.error_description ?? "Anmeldung fehlgeschlagen")")
        }
        token = t
        expiry = Date().addingTimeInterval((resp.expires_in ?? 3600) - 120)
        return t
    }
}

struct DeviantArtProvider: ImageProvider {
    let kind = SourceKind.deviantart

    private struct Response: Decodable { let results: [Item] }
    private struct Item: Decodable {
        let deviationid: String
        let title: String?
        let url: String?
        let author: Author?
        let content: Media?
        let preview: Media?
        let thumbs: [Media]?
        let is_mature: Bool?
    }
    private struct Author: Decodable { let username: String? }
    private struct Media: Decodable { let src: String }

    func search(query: String, collection: PhotoCollection, page: Int) async throws -> [PhotoCandidate] {
        let token = try await DeviantArtAuth.shared.accessToken()
        // DeviantArt sucht über einzelne Tags ohne Leerzeichen – wir nehmen das aussagekräftigste Wort.
        let words = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
        let tag = words.max(by: { $0.count < $1.count }) ?? "photography"
        var comps = URLComponents(string: "https://www.deviantart.com/api/v1/oauth2/browse/tags")!
        comps.queryItems = [
            .init(name: "tag", value: tag),
            .init(name: "limit", value: "24"),
            .init(name: "offset", value: String((page - 1) * 24)),
            .init(name: "mature_content", value: collection.allowNudity ? "true" : "false"),
            .init(name: "access_token", value: token)
        ]
        let resp = try await HTTP.json(Response.self, comps.url!)
        return resp.results.compactMap { r in
            if !collection.allowNudity, r.is_mature == true { return nil }
            guard let img = HTTP.secureURL(r.content?.src ?? r.preview?.src) else { return nil }
            let thumb = HTTP.secureURL(r.thumbs?.last?.src ?? r.preview?.src) ?? img
            return PhotoCandidate(
                id: "deviantart:\(r.deviationid)", source: .deviantart, origin: "deviantart",
                title: r.title ?? "", author: r.author?.username ?? "",
                imageURL: img, fallbackImageURL: HTTP.secureURL(r.preview?.src), thumbURL: thumb,
                pageURL: HTTP.secureURL(r.url),
                tags: [tag] + (r.title ?? "").split(separator: " ").map(String.init), query: query)
        }
    }
}

// MARK: - ArtStation (inoffizielle Such-Schnittstelle, kann sich ändern)

struct ArtStationProvider: ImageProvider {
    let kind = SourceKind.artstation

    private struct Response: Decodable { let data: [Item] }
    private struct Item: Decodable {
        let hash_id: String
        let title: String?
        let url: String?
        let smaller_square_cover_url: String?
        let user: User?
        let hide_as_adult: Bool?
    }
    private struct User: Decodable { let username: String?; let full_name: String? }

    func search(query: String, collection: PhotoCollection, page: Int) async throws -> [PhotoCandidate] {
        var req = URLRequest(url: URL(string: "https://www.artstation.com/api/v2/search/projects.json")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "query": query, "page": page, "per_page": 30,
            "sorting": "relevance", "pro_first": "1",
            "filters": [String](), "additional_fields": [String]()
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await HTTP.data(req)
        let resp = try JSONDecoder().decode(Response.self, from: data)
        return resp.data.compactMap { r in
            if !collection.allowNudity, r.hide_as_adult == true { return nil }
            guard let coverString = r.smaller_square_cover_url, let cover = HTTP.secureURL(coverString) else { return nil }
            let large = HTTP.secureURL(coverString.replacingOccurrences(of: "/smaller_square/", with: "/large/")) ?? cover
            return PhotoCandidate(
                id: "artstation:\(r.hash_id)", source: .artstation, origin: "artstation",
                title: r.title ?? "", author: r.user?.full_name ?? r.user?.username ?? "",
                imageURL: large, fallbackImageURL: cover, thumbURL: cover,
                pageURL: HTTP.secureURL(r.url),
                tags: (r.title ?? "").split(separator: " ").map(String.init), query: query)
        }
    }
}

// MARK: - Pinterest-Boards & beliebige RSS-/Atom-Feeds

struct RSSProvider: ImageProvider {
    let kind = SourceKind.rss

    /// Wandelt eine Pinterest-Board-Adresse in die RSS-Adresse um.
    static func normalizedFeedURL(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        if s.contains("pinterest."), !s.hasSuffix(".rss") {
            if let q = s.firstIndex(of: "?") { s = String(s[..<q]) }
            while s.hasSuffix("/") { s.removeLast() }
            s += ".rss"
        }
        return HTTP.secureURL(s)
    }

    func search(query: String, collection: PhotoCollection, page: Int) async throws -> [PhotoCandidate] {
        let feeds = collection.feeds.compactMap(Self.normalizedFeedURL).prefix(8)
        guard !feeds.isEmpty else { return [] }
        var all: [PhotoCandidate] = []
        var lastError: Error?
        for feed in feeds {
            do {
                let data = try await HTTP.get(feed, headers: ["Accept": "application/rss+xml, application/atom+xml, */*"])
                let items = RSSParser.parse(data)
                all += items.compactMap { candidate(from: $0, feed: feed, query: query) }
            } catch {
                lastError = error
            }
        }
        if all.isEmpty, let e = lastError { throw e }
        return all
    }

    private func candidate(from item: RSSParser.Item, feed: URL, query: String) -> PhotoCandidate? {
        var imageString = item.mediaURLs.first
        if imageString == nil { imageString = RSSParser.firstImage(in: item.description) }
        guard let raw = imageString, let original = HTTP.secureURL(raw) else { return nil }
        var display = original
        if raw.contains("pinimg.com") {
            // Pinterest liefert im Feed 236px-Vorschauen – größere Variante verwenden.
            for small in ["/236x/", "/474x/", "/170x/"] where raw.contains(small) {
                display = HTTP.secureURL(raw.replacingOccurrences(of: small, with: "/736x/")) ?? original
            }
        }
        let host = feed.host ?? "feed"
        let origin = host.contains("pinterest") ? "pinterest" : host.replacingOccurrences(of: "www.", with: "")
        let link = HTTP.secureURL(item.link)
        return PhotoCandidate(
            id: "rss:\(item.guid.isEmpty ? (item.link.isEmpty ? raw : item.link) : item.guid)",
            source: .rss, origin: origin,
            title: item.title, author: "",
            imageURL: display, fallbackImageURL: original, thumbURL: original,
            pageURL: link, tags: item.categories + item.title.split(separator: " ").map(String.init),
            query: query)
    }
}

final class RSSParser: NSObject, XMLParserDelegate {
    struct Item {
        var title = ""
        var link = ""
        var guid = ""
        var description = ""
        var mediaURLs: [String] = []
        var categories: [String] = []
    }

    private var items: [Item] = []
    private var current: Item?
    private var text = ""

    static func parse(_ data: Data) -> [Item] {
        let p = RSSParser()
        let parser = XMLParser(data: data)
        parser.delegate = p
        parser.parse()
        return p.items
    }

    static func firstImage(in html: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: "<img[^>]+src=[\"']([^\"']+)[\"']", options: [.caseInsensitive]) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let m = re.firstMatch(in: html, range: range), let r = Range(m.range(at: 1), in: html) else { return nil }
        return String(html[r])
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        let el = (qName ?? name).lowercased()
        if el == "item" || el == "entry" { current = Item() }
        text = ""
        guard current != nil else { return }
        switch el {
        case "enclosure", "media:content", "media:thumbnail":
            if let u = attributes["url"] {
                let type = attributes["type"] ?? "image"
                if type.hasPrefix("image") || el == "media:thumbnail" { current?.mediaURLs.append(u) }
            }
        case "link":
            if let href = attributes["href"], (attributes["rel"] ?? "alternate") == "alternate" {
                current?.link = href
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        let el = (qName ?? name).lowercased()
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { text = "" }
        guard current != nil else { return }
        switch el {
        case "title": current?.title = value
        case "link": if !value.isEmpty { current?.link = value }
        case "guid", "id": current?.guid = value
        case "description", "content:encoded", "content", "summary": current?.description += value
        case "category": if !value.isEmpty { current?.categories.append(value) }
        case "item", "entry":
            if let c = current { items.append(c) }
            current = nil
        default: break
        }
    }
}
