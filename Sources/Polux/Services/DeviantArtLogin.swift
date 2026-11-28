import AppKit
import AuthenticationServices

/// Anmeldung mit dem eigenen DeviantArt-Konto (OAuth2 „Authorization Code“).
/// Die Anmeldeseite öffnet sich in einem Systemfenster; Passwörter sieht Polux nie.
@MainActor
final class DeviantArtLogin: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = DeviantArtLogin()

    @Published private(set) var username: String? = Keychain.get(.deviantartUser)
    @Published private(set) var isLoggedIn = DeviantArtAuth.hasUserLogin
    @Published private(set) var busy = false
    @Published var message: String?

    private var session: ASWebAuthenticationSession?

    var loginExpired: Bool { UserDefaults.standard.bool(forKey: "deviantartLoginExpired") && !isLoggedIn }

    func refreshState() {
        isLoggedIn = DeviantArtAuth.hasUserLogin
        username = isLoggedIn ? Keychain.get(.deviantartUser) : nil
    }

    func login() {
        guard !busy else { return }
        message = nil
        let state = UUID().uuidString
        let url: URL
        do { url = try DeviantArtAuth.authorizeURL(state: state) } catch {
            message = "Bitte zuerst Client ID und Client Secret eintragen."
            return
        }
        busy = true
        let s = ASWebAuthenticationSession(url: url, callbackURLScheme: DeviantArtAuth.callbackScheme) { [weak self] cb, error in
            Task { @MainActor in await self?.finish(callback: cb, error: error, state: state) }
        }
        anchor = NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible }
        s.presentationContextProvider = self
        s.prefersEphemeralWebBrowserSession = false
        session = s
        if !s.start() {
            busy = false
            message = "Das Anmeldefenster konnte nicht geöffnet werden."
        }
    }

    private func finish(callback: URL?, error: Error?, state: String) async {
        defer { busy = false; session = nil }
        if let error {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
            message = "Anmeldung abgebrochen: \(error.localizedDescription)"
            return
        }
        guard let callback, let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems else {
            message = "DeviantArt hat keine Antwort geliefert."
            return
        }
        if let err = items.first(where: { $0.name == "error" })?.value {
            let desc = items.first(where: { $0.name == "error_description" })?.value
            message = Self.explainAuthorizeError(err, desc)
            return
        }
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            message = "Ungültige Antwort von DeviantArt – bitte erneut versuchen."
            return
        }
        do {
            let user = try await DeviantArtAuth.shared.completeLogin(code: code)
            refreshState()
            username = user
            message = nil
            await ConnectionTester.shared.test(.deviantart)
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func logout() async {
        await DeviantArtAuth.shared.logout()
        refreshState()
        await ConnectionTester.shared.test(.deviantart)
    }

    static func explainAuthorizeError(_ error: String, _ desc: String?) -> String {
        switch error {
        case "access_denied": return "Anmeldung bei DeviantArt nicht erlaubt."
        case "invalid_request" where (desc ?? "").lowercased().contains("redirect"):
            return "DeviantArt kennt die Rücksprung-Adresse nicht. Bitte in den App-Einstellungen bei DeviantArt unter „OAuth2 Redirect URI Whitelist“ \(DeviantArtAuth.redirectURI) eintragen und speichern."
        default: return "DeviantArt meldet: \(desc ?? error)"
        }
    }

    /// Vor dem Start auf dem Hauptthread gesetzt; AuthenticationServices fragt es danach ab.
    nonisolated(unsafe) private var anchor: NSWindow?

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor ?? NSWindow()
    }
}
