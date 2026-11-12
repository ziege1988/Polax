import Foundation

enum HTTP {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 25
        c.timeoutIntervalForResource = 90
        c.httpAdditionalHeaders = ["User-Agent": "Polux/\(AppInfo.version) (macOS; inspiration widget)"]
        c.urlCache = URLCache(memoryCapacity: 2 * 1024 * 1024, diskCapacity: 40 * 1024 * 1024)
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    static func data(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ProviderError.http(http.statusCode, request.url?.host ?? "Server")
        }
        return data
    }

    static func get(_ url: URL, headers: [String: String] = [:], timeout: TimeInterval = 25) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        return try await data(req)
    }

    static func json<T: Decodable>(_ type: T.Type, _ url: URL, headers: [String: String] = [:]) async throws -> T {
        var h = headers
        h["Accept"] = h["Accept"] ?? "application/json"
        let data = try await get(url, headers: h)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Erzwingt HTTPS (App Transport Security) und ergänzt protokoll-relative URLs.
    static func secureURL(_ string: String?) -> URL? {
        guard var s = string?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        if s.hasPrefix("//") { s = "https:" + s }
        if s.hasPrefix("http://") { s = "https://" + s.dropFirst("http://".count) }
        guard s.hasPrefix("https://") else { return nil }
        return URL(string: s) ?? URL(string: s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
    }
}
