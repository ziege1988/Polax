import CryptoKit
import Foundation
import Security

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

/// Akzeptiert Zahl oder Text (manche APIs liefern IDs uneinheitlich).
struct FlexString: Decodable {
    let value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int.self) { value = String(i) }
        else { value = "" }
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
        let license: String?
        let license_version: String?
    }
    private struct Tag: Decodable { let name: String }

    static func licenseLabel(_ license: String?, _ version: String?) -> String? {
        guard let l = license?.lowercased(), !l.isEmpty else { return nil }
        switch l {
        case "cc0": return "CC0"
        case "pdm": return "Public Domain"
        default: return "CC \(l.uppercased())" + (version.map { " \($0)" } ?? "")
        }
    }

    func search(query: String, collection: PhotoCollection, page: Int) async throws -> [PhotoCandidate] {
        var comps = URLComponents(string: "https://api.openverse.org/v1/images/")!
        var items: [URLQueryItem] = [
            .init(name: "q", value: query),
            .init(name: "page_size", value: "20"),
            .init(name: "page", value: String(page))
        ]
        if collection.allowNudity { items.append(.init(name: "mature", value: "true")) }
        // Nur echte Fotografie-Quellen: Museums- und Archivbestände (Wikimedia, Museen) enthalten
        // viele abfotografierte Gemälde, die Openverse trotzdem als „photograph“ einstuft.
        items.append(.init(name: "category", value: "photograph"))
        items.append(.init(name: "source", value: "flickr,stocksnap,wordpress"))
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
                tags: (r.tags ?? []).map(\.name), query: query,
                license: Self.licenseLabel(r.license, r.license_version))
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
                query: query, license: "Unsplash-Lizenz")
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
        let license: FlexString?
    }

    static func licenseLabel(_ id: String?) -> String? {
        switch id ?? "" {
        case "1": return "CC BY-NC-SA 2.0"
        case "2": return "CC BY-NC 2.0"
        case "3": return "CC BY-NC-ND 2.0"
        case "4": return "CC BY 2.0"
        case "5": return "CC BY-SA 2.0"
        case "6": return "CC BY-ND 2.0"
        case "7": return "Kein bekanntes Copyright"
        case "9": return "CC0"
        case "10": return "Public Domain"
        default: return nil
        }
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
            .init(name: "extras", value: "url_l,url_c,url_z,url_q,tags,owner_name,license"),
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
                tags: (r.tags ?? "").split(separator: " ").map(String.init), query: query,
                license: Self.licenseLabel(r.license?.value))
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
                tags: alt.split(separator: " ").map(String.init), query: query, license: "Pexels-Lizenz")
        }
    }
}

// MARK: - DeviantArt (OAuth Client Credentials)

actor DeviantArtAuth {
    static let shared = DeviantArtAuth()
    private var token: String?
    private var expiry = Date.distantPast

    /// Muss bei DeviantArt unter „OAuth2 Redirect URI Whitelist“ eingetragen sein.
    static let redirectURI = "polux://deviantart-login"
    static let callbackScheme = "polux"
    static let scopes = "browse user"

    /// Angemeldet mit dem eigenen Konto (Akt-Inhalte unverwischt, eigene Filtereinstellungen).
    nonisolated static var hasUserLogin: Bool { Keychain.has(.deviantartRefresh) }

    private struct TokenResponse: Decodable {
        let access_token: String?
        let refresh_token: String?
        let expires_in: Double?
        let error: String?
        let error_description: String?
    }

    func reset() {
        token = nil
        expiry = .distantPast
    }

    /// Bereinigt eingefügte Werte: Leerzeichen, Zeilenumbrüche, Beschriftungen wie „client_id: 12345“.
    static func clean(_ raw: String, digitsOnly: Bool) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if digitsOnly {
            // client_id ist eine Zahl – längste Ziffernfolge übernehmen.
            let runs = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
            return runs.max(by: { $0.count < $1.count }) ?? trimmed
        }
        // client_secret: letztes „Wort“ ohne Leer- und Anführungszeichen
        let parts = trimmed.components(separatedBy: CharacterSet(charactersIn: " \t\n\r:=\"'"))
            .filter { !$0.isEmpty }
        return parts.last ?? trimmed
    }

    /// Für die App-Daten (client_id, client_secret).
    private static func credentials() throws -> (id: String, secret: String) {
        guard let rawID = Keychain.get(.deviantartID), let rawSecret = Keychain.get(.deviantartSecret) else {
            throw ProviderError.missingCredentials(.deviantart)
        }
        return (clean(rawID, digitsOnly: true), clean(rawSecret, digitsOnly: false))
    }

    /// Adresse der DeviantArt-Anmeldeseite für das eigene Konto.
    /// PKCE: zufälliger Prüfwert für die Anmeldung (von DeviantArt verlangt).
    static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func authorizeURL(state: String, verifier: String) throws -> URL {
        let c = try credentials()
        var comps = URLComponents(string: "https://www.deviantart.com/oauth2/authorize")!
        comps.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: c.id),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: scopes),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: codeChallenge(for: verifier)),
            .init(name: "code_challenge_method", value: "S256")
        ]
        return comps.url!
    }

    /// Tauscht den Code aus der Anmeldung gegen Tokens und merkt sich das Konto.
    func completeLogin(code: String, verifier: String) async throws -> String {
        let c = try Self.credentials()
        try await tokenRequest([
            "grant_type": "authorization_code", "client_id": c.id, "client_secret": c.secret,
            "redirect_uri": Self.redirectURI, "code": code, "code_verifier": verifier])
        let user = await Self.whoami(token: token ?? "") ?? "DeviantArt-Konto"
        Keychain.set(user, for: .deviantartUser)
        UserDefaults.standard.set(false, forKey: "deviantartLoginExpired")
        return user
    }

    func logout() {
        Keychain.set("", for: .deviantartRefresh)
        Keychain.set("", for: .deviantartUser)
        reset()
    }

    /// POST an den Token-Endpunkt; speichert Access- und (neues) Refresh-Token.
    @discardableResult
    private func tokenRequest(_ fields: [String: String]) async throws -> TokenResponse {
        var form = URLComponents()
        form.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: URL(string: "https://www.deviantart.com/oauth2/token")!, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = (form.percentEncodedQuery ?? "").data(using: .utf8)
        let (data, response) = try await HTTP.session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let resp = try? JSONDecoder().decode(TokenResponse.self, from: data)
        guard (200..<300).contains(code), let resp, let t = resp.access_token else {
            throw ProviderError.api("DeviantArt-Anmeldung abgelehnt: "
                                    + Self.explain(error: resp?.error, description: resp?.error_description, code: code))
        }
        token = t
        expiry = Date().addingTimeInterval((resp.expires_in ?? 3600) - 120)
        if let r = resp.refresh_token, !r.isEmpty {
            Keychain.set(r, for: .deviantartRefresh)
        }
        return resp
    }

    private static func whoami(token: String) async -> String? {
        guard !token.isEmpty else { return nil }
        var req = URLRequest(url: URL(string: "https://www.deviantart.com/api/v1/oauth2/user/whoami")!, timeoutInterval: 15)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        struct Who: Decodable { let username: String? }
        guard let (data, _) = try? await HTTP.session.data(for: req) else { return nil }
        return (try? JSONDecoder().decode(Who.self, from: data))?.username
    }

    func accessToken() async throws -> String {
        if let t = token, Date() < expiry { return t }
        // 1) Eigenes Konto: Token erneuern (gilt ca. 3 Monate, verlängert sich bei Nutzung).
        if let refresh = Keychain.get(.deviantartRefresh) {
            let c = try Self.credentials()
            do {
                try await tokenRequest(["grant_type": "refresh_token", "client_id": c.id,
                                        "client_secret": c.secret, "refresh_token": refresh])
                if let t = token { return t }
            } catch {
                // Anmeldung abgelaufen/zurückgezogen → abmelden und mit App-Zugang weitermachen.
                NSLog("Polux: DeviantArt-Konto-Anmeldung abgelaufen: \(error)")
                Keychain.set("", for: .deviantartRefresh)
                UserDefaults.standard.set(true, forKey: "deviantartLoginExpired")
            }
        }
        guard let rawID = Keychain.get(.deviantartID), let rawSecret = Keychain.get(.deviantartSecret) else {
            throw ProviderError.missingCredentials(.deviantart)
        }
        let id = Self.clean(rawID, digitsOnly: true)
        let secret = Self.clean(rawSecret, digitsOnly: false)

        // DeviantArt erlaubt mehrere Anmeldearten – nacheinander probieren.
        let tokenURL = URL(string: "https://www.deviantart.com/oauth2/token")!
        var form = URLComponents()
        form.queryItems = [
            .init(name: "grant_type", value: "client_credentials"),
            .init(name: "client_id", value: id),
            .init(name: "client_secret", value: secret)
        ]
        let body = form.percentEncodedQuery ?? ""

        var post = URLRequest(url: tokenURL, timeoutInterval: 20)
        post.httpMethod = "POST"
        post.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        post.httpBody = body.data(using: .utf8)

        var basic = URLRequest(url: tokenURL, timeoutInterval: 20)
        basic.httpMethod = "POST"
        basic.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        basic.setValue("Basic " + Data("\(id):\(secret)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        basic.httpBody = "grant_type=client_credentials".data(using: .utf8)

        let get = URLRequest(url: URL(string: tokenURL.absoluteString + "?" + body)!, timeoutInterval: 20)

        var lastProblem = "Anmeldung fehlgeschlagen"
        for var req in [post, basic, get] {
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await HTTP.session.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let resp = try? JSONDecoder().decode(TokenResponse.self, from: data)
            if (200..<300).contains(code), let t = resp?.access_token {
                token = t
                expiry = Date().addingTimeInterval((resp?.expires_in ?? 3600) - 120)
                return t
            }
            lastProblem = Self.explain(error: resp?.error, description: resp?.error_description, code: code)
            guard code == 400 || code == 401 else { break }   // andere Fehler: nicht weiter probieren
        }
        throw ProviderError.api("DeviantArt-Anmeldung abgelehnt: " + lastProblem)
    }

    static func explain(error: String?, description: String?, code: Int) -> String {
        switch error {
        case "invalid_client":
            return "client_id und client_secret passen nicht zusammen. Bitte beide Werte unter deviantart.com/developers/apps neu kopieren (client_id = Zahl, client_secret = lange Zeichenfolge)."
        case "unauthorized_client":
            return "Die App darf sich so nicht anmelden. In den App-Einstellungen bei DeviantArt prüfen, ob die App veröffentlicht ist."
        case "invalid_request":
            return "Unvollständige Anfrage (\(description ?? "fehlende Angaben"))."
        default:
            if let d = description, !d.isEmpty { return "\(d) (HTTP \(code))" }
            return "HTTP \(code)"
        }
    }
}

struct DeviantArtProvider: ImageProvider {
    let kind = SourceKind.deviantart

    private struct Response: Decodable { let results: [Item] }

    /// Ruft einen DeviantArt-Browse-Endpunkt ab; liefert die Treffer oder einen verständlichen Fehler.
    private func fetch(_ path: String, _ items: [URLQueryItem], token: String) async throws -> [Item] {
        var comps = URLComponents(string: "https://www.deviantart.com/api/v1/oauth2/" + path)!
        comps.queryItems = items + [.init(name: "access_token", value: token)]
        var req = URLRequest(url: comps.url!, timeoutInterval: 25)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await HTTP.session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            struct Err: Decodable { let error: String?; let error_description: String? }
            let e = try? JSONDecoder().decode(Err.self, from: data)
            if code == 401 || code == 403 { await DeviantArtAuth.shared.reset() }
            throw ProviderError.api("DeviantArt: Anmeldung ok, aber Abruf abgelehnt – "
                                    + (e?.error_description ?? "HTTP \(code)"))
        }
        return try JSONDecoder().decode(Response.self, from: data).results
    }

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
    /// Entfernt eine Weichzeichner-Anweisung („,blur_30“) aus DeviantArt-/Wix-Bildadressen.
    static func unblurred(_ src: String?) -> String? {
        guard let src else { return nil }
        return src.replacingOccurrences(of: #",blu?r_[0-9]+"#, with: "", options: .regularExpression)
    }

    private struct Author: Decodable { let username: String? }
    private struct Media: Decodable { let src: String }

    func search(query: String, collection: PhotoCollection, page: Int) async throws -> [PhotoCandidate] {
        let token = try await DeviantArtAuth.shared.accessToken()
        let offset = String((page - 1) * 24)
        let mature = collection.allowNudity ? "true" : "false"
        let words = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }

        // 1) Volltextsuche mit dem ganzen Suchbegriff („experimental nude“ statt nur „experimental“)
        var results: [Item] = []
        var usedTags: [String] = words
        if let found = try? await fetch("browse/popular", [
            .init(name: "q", value: query), .init(name: "timerange", value: "alltime"),
            .init(name: "limit", value: "24"), .init(name: "offset", value: offset),
            .init(name: "mature_content", value: mature)], token: token), !found.isEmpty {
            results = found
        } else if let found = try? await fetch("browse/newest", [
            .init(name: "q", value: query), .init(name: "limit", value: "24"),
            .init(name: "offset", value: offset), .init(name: "mature_content", value: mature)], token: token),
                  !found.isEmpty {
            results = found
        } else {
            // 2) Rückfall: Tag-Suche – reihum über die Wörter des Suchbegriffs statt immer nur das längste
            let generic = StyleEngine.genericTokens
            let candidates = words.filter { !generic.contains($0) }
            let pool = candidates.isEmpty ? words : candidates
            let tag = pool.isEmpty ? "photography" : pool[(page - 1) % pool.count]
            usedTags = [tag]
            results = try await fetch("browse/tags", [
                .init(name: "tag", value: tag), .init(name: "limit", value: "24"),
                .init(name: "offset", value: offset), .init(name: "mature_content", value: mature)], token: token)
        }
        let resp = Response(results: results)
        let tag = usedTags.joined(separator: " ")
        return resp.results.compactMap { r in
            if !collection.allowNudity, r.is_mature == true { return nil }
            guard let img = HTTP.secureURL(Self.unblurred(r.content?.src ?? r.preview?.src)) else { return nil }
            let thumb = HTTP.secureURL(Self.unblurred(r.thumbs?.last?.src ?? r.preview?.src)) ?? img
            return PhotoCandidate(
                id: "deviantart:\(r.deviationid)", source: .deviantart, origin: "deviantart",
                title: r.title ?? "", author: r.author?.username ?? "",
                imageURL: img, fallbackImageURL: HTTP.secureURL(Self.unblurred(r.preview?.src)), thumbURL: thumb,
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

    /// Browser-ähnliche Kopfzeilen – Pinterest liefert Feeds an unbekannte Programme teils nicht aus.
    static let browserHeaders: [String: String] = [
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15",
        "Accept": "application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.5",
        "Accept-Language": "de-DE,de;q=0.9,en;q=0.8"
    ]

    enum FeedProblem: LocalizedError {
        case singlePin, notAFeed, invalid, empty
        var errorDescription: String? {
            switch self {
            case .singlePin:
                return "Das ist ein einzelner Pin, sein Board ließ sich nicht automatisch finden. Bitte das Board öffnen und dessen Link kopieren (App: Board öffnen → Teilen → Link kopieren; Browser: Adresse pinterest.com/nutzer/boardname)."
            case .notAFeed:
                return "Pinterest liefert für diese Adresse keinen Feed. Bitte die Board-Adresse verwenden (pinterest.com/nutzer/boardname)."
            case .invalid:
                return "Ungültige Adresse."
            case .empty:
                return "Der Feed ist leer."
            }
        }
    }

    static func isPinterest(_ host: String) -> Bool {
        host == "pin.it" || host.contains("pinterest.")
    }

    /// Wandelt eine Pinterest-Adresse (auch pinterest.de, de.pinterest.com, Profil, Board-Abschnitt)
    /// in die RSS-Adresse um. Andere Feeds bleiben unverändert. Kurzlinks (pin.it) löst `resolve` auf.
    static func normalizedFeedURL(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        guard var comps = URLComponents(string: s), let host = comps.host?.lowercased() else { return nil }
        guard isPinterest(host), host != "pin.it" else { return HTTP.secureURL(s) }

        var parts = comps.path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        if parts.first == "pin" { return nil }                              // einzelner Pin
        if let last = parts.last, last.hasSuffix(".rss") {
            parts[parts.count - 1] = String(last.dropLast(4))
        }
        parts.removeAll { ["_saved", "_created", "_shop", "_profile", "pins", "boards"].contains($0) }
        comps.scheme = "https"
        comps.host = "www.pinterest.com"                                   // Länderdomains → .com
        comps.query = nil
        comps.fragment = nil
        switch parts.count {
        case 0: return nil
        case 1: comps.path = "/\(parts[0])/feed.rss"                        // Profil → alle Pins
        default: comps.path = "/\(parts[0])/\(parts[1]).rss"                // Board (Abschnitte → ganzes Board)
        }
        return comps.url
    }

    /// Löst Kurzlinks (pin.it) auf und liefert die Feed-Adresse.
    static func resolve(_ raw: String) async throws -> URL {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        if let host = URL(string: s)?.host?.lowercased(), host == "pin.it", let short = URL(string: s) {
            var req = URLRequest(url: short, timeoutInterval: 20)
            for (k, v) in browserHeaders { req.setValue(v, forHTTPHeaderField: k) }
            let (_, response) = try await HTTP.session.data(for: req)
            guard let finalURL = response.url?.absoluteString else { throw FeedProblem.invalid }
            s = finalURL
        }
        if let comps = URLComponents(string: s), comps.path.hasPrefix("/pin/"), let pinURL = URL(string: s) {
            // Einzelner Pin: das Board ermitteln, auf dem er gespeichert ist, und dessen Feed verwenden.
            if let board = try? await boardOfPin(pinURL), let url = normalizedFeedURL(board) { return url }
            throw FeedProblem.singlePin
        }
        guard let url = normalizedFeedURL(s) else { throw FeedProblem.invalid }
        return url
    }

    /// Liest aus der Pin-Seite das Board („Gespeichert in …“), z. B. „https://www.pinterest.com/nutzer/board/“.
    static func boardOfPin(_ pinURL: URL) async throws -> String? {
        var req = URLRequest(url: pinURL, timeoutInterval: 20)
        for (k, v) in browserHeaders { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("text/html,application/xhtml+xml,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let data = try await HTTP.data(req)
        var html = String(decoding: data, as: UTF8.self)
        html = html.replacingOccurrences(of: "\\/", with: "/").replacingOccurrences(of: "\\\"", with: "\"")

        let blocked: Set<String> = ["pin", "search", "ideas", "today", "_tools", "business", "resource", "settings",
                                    "login", "explore", "videos", "shopping", "_saved", "_created", "categories"]
        func valid(_ path: String) -> String? {
            let parts = path.split(separator: "/").map(String.init)
            guard parts.count >= 2, !blocked.contains(parts[0]), !parts[1].hasPrefix("_") else { return nil }
            return "https://www.pinterest.com/\(parts[0])/\(parts[1])/"
        }
        // 1) JSON-Daten der Seite: "board":{ … "url":"/nutzer/board/" … }
        let patterns = [
            #""board"\s*:\s*\{[^{}]{0,800}?"url"\s*:\s*"(/[^"/]+/[^"/]+/)""#,
            #""url"\s*:\s*"(/[^"/]+/[^"/]+/)"[^{}]{0,800}?"type"\s*:\s*"board""#,
            // 2) Sichtbarer Link „Gespeichert in …“
            #"href="(/[^"/]+/[^"/]+/)"[^>]*data-test-id="board"#
        ]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            for m in re.matches(in: html, range: range) {
                if let r = Range(m.range(at: 1), in: html), let board = valid(String(html[r])) { return board }
            }
        }
        return nil
    }

    /// Lädt und liest einen einzelnen Feed.
    static func fetchItems(_ raw: String) async throws -> (feed: URL, items: [RSSParser.Item]) {
        let r = try await fetchItemsDetailed(raw)
        return (r.feed, r.items)
    }

    /// Robuster Abruf: bis zu 3 Versuche mit Pause; Board-Adressen von Pins werden gemerkt;
    /// ist Pinterest kurz nicht erreichbar, werden die zuletzt geladenen Bilder (bis 48 h) weiterverwendet.
    static func fetchItemsDetailed(_ raw: String) async throws -> (feed: URL, items: [RSSParser.Item], fromCache: Bool) {
        let feed: URL
        if let known = await FeedCache.shared.resolved(raw) {
            feed = known
        } else {
            feed = try await withRetry { try await resolve(raw) }
            await FeedCache.shared.setResolved(raw, feed)
        }
        let headers = isPinterest(feed.host ?? "") ? browserHeaders : ["Accept": browserHeaders["Accept"]!]
        do {
            let items: [RSSParser.Item] = try await withRetry {
                let data = try await HTTP.get(feed, headers: headers)
                let head = String(decoding: data.prefix(400), as: UTF8.self).lowercased()
                if head.contains("<!doctype html") || head.contains("<html") { throw FeedProblem.notAFeed }
                let items = RSSParser.parse(data)
                if items.isEmpty { throw FeedProblem.empty }
                return items
            }
            await FeedCache.shared.store(items, for: feed)
            return (feed, items, false)
        } catch {
            if let cached = await FeedCache.shared.items(for: feed, maxAge: 48 * 3600) {
                return (feed, cached, true)
            }
            if case FeedProblem.empty = error { return (feed, [], false) }
            throw error
        }
    }

    /// Wiederholt eine Anfrage bei vorübergehenden Fehlern (Zeitüberschreitung, 429/5xx, HTML statt Feed).
    static func withRetry<T>(_ attempts: Int = 3, _ op: () async throws -> T) async throws -> T {
        var lastError: Error = FeedProblem.invalid
        for i in 0..<attempts {
            do { return try await op() } catch {
                lastError = error
                var permanent = false
                if case ProviderError.http(let code, _) = error, code == 404 || code == 410 { permanent = true }
                if case FeedProblem.singlePin = error { permanent = true }
                if case FeedProblem.invalid = error { permanent = true }
                if permanent || i == attempts - 1 { break }
                try? await Task.sleep(nanoseconds: UInt64(1_200_000_000 * (i + 1)) + UInt64.random(in: 0...400_000_000))
            }
        }
        throw lastError
    }

    func search(query: String, collection: PhotoCollection, page: Int) async throws -> [PhotoCandidate] {
        let feeds = collection.feeds.prefix(8)
        guard !feeds.isEmpty else { return [] }
        var all: [PhotoCandidate] = []
        var lastError: Error?
        for raw in feeds {
            do {
                let (feed, items) = try await Self.fetchItems(raw)
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
    struct Item: Codable {
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

/// Merkt sich aufgelöste Board-Adressen und zuletzt geladene Feeds (auch über Neustarts hinweg).
actor FeedCache {
    static let shared = FeedCache()

    private struct Entry: Codable { var date: Date; var items: [RSSParser.Item] }
    private struct Store: Codable {
        var resolved: [String: String] = [:]
        var feeds: [String: Entry] = [:]
    }

    private var data = Store()
    private var loaded = false
    private var fileURL: URL { Paths.caches.appendingPathComponent("feeds.json") }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let d = try? Data(contentsOf: fileURL), let s = try? JSONDecoder().decode(Store.self, from: d) { data = s }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(data) { try? d.write(to: fileURL, options: .atomic) }
    }

    func resolved(_ raw: String) -> URL? {
        load()
        return data.resolved[raw].flatMap(URL.init(string:))
    }

    func setResolved(_ raw: String, _ url: URL) {
        load()
        data.resolved[raw] = url.absoluteString
        save()
    }

    func items(for feed: URL, maxAge: TimeInterval) -> [RSSParser.Item]? {
        load()
        guard let e = data.feeds[feed.absoluteString], Date().timeIntervalSince(e.date) < maxAge, !e.items.isEmpty else { return nil }
        return e.items
    }

    func store(_ items: [RSSParser.Item], for feed: URL) {
        load()
        data.feeds[feed.absoluteString] = Entry(date: Date(), items: Array(items.prefix(150)))
        save()
    }
}
