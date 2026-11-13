import Foundation
import AppKit
import CryptoKit

/// Prüft GitHub-Releases auf neue Versionen und installiert sie mit einem Klick:
/// herunterladen → Prüfsumme und App-Kennung prüfen → App ersetzen → neu starten.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case downloading(version: String)
        case installing(version: String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    /// Download-Infos zur gefundenen Version.
    private var pending: (version: String, zip: URL?, digest: String?, page: URL)?

    var availableVersion: String? {
        switch state {
        case .available(let v, _), .downloading(let v), .installing(let v): return v
        default: return nil
        }
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
        let assets: [Asset]?
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
            let digest: String?
        }
    }

    // MARK: Prüfen

    func check() async {
        state = .checking
        let url = URL(string: "https://api.github.com/repos/\(AppInfo.updateRepository)/releases/latest")!
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await HTTP.session.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 404 {
                state = .failed("Noch keine veröffentlichte Version gefunden (oder das Repository ist privat).")
                return
            }
            guard (200..<300).contains(code) else {
                state = .failed("GitHub antwortet mit HTTP \(code).")
                return
            }
            let rel = try JSONDecoder().decode(Release.self, from: data)
            AppSettings.shared.lastUpdateCheck = Date()
            let latest = rel.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            if Self.isVersion(latest, newerThan: AppInfo.version) {
                let zip = rel.assets?.first { $0.name.lowercased().hasSuffix(".zip") }
                let page = URL(string: rel.html_url)!
                pending = (latest, zip.flatMap { URL(string: $0.browser_download_url) }, zip?.digest, page)
                state = .available(version: latest, url: page)
            } else {
                pending = nil
                state = .upToDate
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Höchstens einmal täglich automatisch prüfen; bei neuer Version einmalig nachfragen.
    func checkIfDue() async {
        guard AppSettings.shared.autoCheckUpdates else { return }
        if let last = AppSettings.shared.lastUpdateCheck, Date().timeIntervalSince(last) < 24 * 3600 { return }
        await check()
        if let v = availableVersion, UserDefaults.standard.string(forKey: "updatePromptedVersion") != v {
            UserDefaults.standard.set(v, forKey: "updatePromptedVersion")
            promptInstall(version: v)
        }
    }

    private func promptInstall(version: String) {
        let alert = NSAlert()
        alert.messageText = "Polux \(version) ist verfügbar"
        alert.informativeText = "Du hast Version \(AppInfo.version). Jetzt aktualisieren? Polux startet danach automatisch neu – Sammlungen und Likes bleiben erhalten."
        alert.addButton(withTitle: "Jetzt aktualisieren")
        alert.addButton(withTitle: "Später")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await install() }
        }
    }

    // MARK: Installieren

    func install() async {
        guard let p = pending else { return }
        guard let zipURL = p.zip else {
            NSWorkspace.shared.open(p.page)
            return
        }
        let target = Bundle.main.bundleURL
        if let problem = Self.installProblem(for: target) {
            state = .failed(problem)
            return
        }

        state = .downloading(version: p.version)
        do {
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("PoluxUpdate-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

            // 1. Herunterladen
            let (tmp, response) = try await HTTP.session.download(from: zipURL)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ProviderError.http(http.statusCode, "GitHub")
            }
            let zip = work.appendingPathComponent("Polux.zip")
            try FileManager.default.moveItem(at: tmp, to: zip)

            state = .installing(version: p.version)

            // 2. Prüfsumme (von GitHub veröffentlicht) vergleichen
            if let digest = p.digest, digest.hasPrefix("sha256:") {
                let expected = String(digest.dropFirst("sha256:".count)).lowercased()
                let actual = try await Task.detached { try Self.sha256(of: zip) }.value
                guard actual == expected else { throw UpdateError.checksum }
            }

            // 3. Entpacken
            let extracted = work.appendingPathComponent("extracted", isDirectory: true)
            try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, extracted.path])
            guard let newApp = Self.findApp(in: extracted) else { throw UpdateError.noApp }

            // 4. Ist es wirklich Polux in der erwarteten Version?
            let info = Bundle(url: newApp)?.infoDictionary
            guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
                throw UpdateError.wrongApp
            }
            let newVersion = info?["CFBundleShortVersionString"] as? String ?? ""
            guard !Self.isVersion(AppInfo.version, newerThan: newVersion) else { throw UpdateError.wrongApp }

            // 5. Austausch nach dem Beenden durch ein kleines Hilfsskript, dann Neustart
            let script = work.appendingPathComponent("install.sh")
            try Self.installScript.write(to: script, atomically: true, encoding: .utf8)
            let helper = Process()
            helper.executableURL = URL(fileURLWithPath: "/bin/sh")
            helper.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier),
                                newApp.path, target.path, work.path]
            try helper.run()

            NotificationCenter.default.post(name: .poluxWillRestartForUpdate, object: nil)
            try? await Task.sleep(nanoseconds: 300_000_000)
            NSApp.terminate(nil)
        } catch {
            state = .failed("Update fehlgeschlagen: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
        }
    }

    /// Prüft, ob die laufende App ersetzt werden kann.
    private static func installProblem(for target: URL) -> String? {
        if target.path.contains("/AppTranslocation/") {
            return "Polux läuft aus einem geschützten Download-Bereich. Bitte Polux.app einmal in den Ordner „Programme“ ziehen und von dort starten – danach klappen Updates automatisch."
        }
        let parent = target.deletingLastPathComponent().path
        if !FileManager.default.isWritableFile(atPath: parent) {
            return "Keine Schreibrechte für „\(parent)“. Bitte das Update manuell installieren."
        }
        return nil
    }

    private static let installScript = """
    #!/bin/sh
    # Wartet, bis Polux beendet ist, tauscht die App aus und startet sie neu.
    PID="$1"; NEW="$2"; TARGET="$3"; WORK="$4"
    i=0
    while kill -0 "$PID" 2>/dev/null; do
      sleep 0.2; i=$((i+1)); [ "$i" -gt 150 ] && exit 1
    done
    rm -rf "$TARGET.old"
    if mv "$TARGET" "$TARGET.old"; then
      if /usr/bin/ditto "$NEW" "$TARGET"; then
        rm -rf "$TARGET.old"
      else
        rm -rf "$TARGET"; mv "$TARGET.old" "$TARGET"
      fi
    fi
    /usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
    /usr/bin/open "$TARGET"
    rm -rf "$WORK"
    """

    enum UpdateError: LocalizedError {
        case checksum, noApp, wrongApp, tool(String)
        var errorDescription: String? {
            switch self {
            case .checksum: return "Die Prüfsumme des Downloads stimmt nicht."
            case .noApp: return "Im Download wurde keine Polux.app gefunden."
            case .wrongApp: return "Der Download enthält keine passende Polux-Version."
            case .tool(let t): return "\(t) ist fehlgeschlagen."
            }
        }
    }

    nonisolated private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError.tool((tool as NSString).lastPathComponent) }
    }

    /// Sucht Polux.app im entpackten Ordner (auch eine Ebene tiefer).
    private static func findApp(in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: nil,
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        for case let url as URL in e where url.pathExtension == "app" {
            return url
        }
        return nil
    }

    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(whereSeparator: { !$0.isNumber }).map { Int($0) ?? 0 }
        }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

extension Notification.Name {
    static let poluxWillRestartForUpdate = Notification.Name("PoluxWillRestartForUpdate")
}
