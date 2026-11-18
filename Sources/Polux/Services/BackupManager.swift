import Foundation
import AppKit
import UniformTypeIdentifiers

/// Datensicherung: Sammlungen, Likes (Vorschaubilder), Notizen und Einstellungen der Sammlungen
/// als ZIP exportieren, wieder einlesen und optional wöchentlich automatisch in iCloud Drive ablegen.
/// API-Schlüssel liegen im macOS-Schlüsselbund und sind bewusst nicht Teil der Sicherung.
@MainActor
enum BackupManager {
    enum BackupError: LocalizedError {
        case tool(String), noLibrary, invalid
        var errorDescription: String? {
            switch self {
            case .tool(let t): return "\(t) ist fehlgeschlagen."
            case .noLibrary: return "In der Datei wurde keine Polux-Sicherung gefunden."
            case .invalid: return "Die Sicherung ist beschädigt oder stammt nicht von Polux."
            }
        }
    }

    // MARK: iCloud Drive

    /// ~/Library/Mobile Documents/com~apple~CloudDocs/Polux Sicherungen (nil, wenn iCloud Drive aus ist).
    static var iCloudFolder: URL? {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: base.path) else { return nil }
        return base.appendingPathComponent("Polux Sicherungen", isDirectory: true)
    }

    static var iCloudAvailable: Bool { iCloudFolder != nil }

    /// Beim Start und täglich aufgerufen: sichert höchstens einmal pro Woche.
    static func autoBackupIfDue(store: LibraryStore) {
        let settings = AppSettings.shared
        guard settings.autoBackupToICloud, let folder = iCloudFolder else { return }
        if let last = settings.lastBackup, Date().timeIntervalSince(last) < 7 * 24 * 3600 { return }
        Task { try? await backupToICloud(store: store, folder: folder) }
    }

    @discardableResult
    static func backupToICloud(store: LibraryStore, folder: URL? = nil) async throws -> URL {
        guard let folder = folder ?? iCloudFolder else { throw BackupError.tool("iCloud Drive") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = folder.appendingPathComponent(fileName())
        try await writeBackup(store: store, to: dest)
        // Nur die letzten 4 automatischen Sicherungen behalten.
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey]))?
            .filter { $0.pathExtension == "zip" && $0.lastPathComponent.hasPrefix("Polux-Sicherung") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
        for old in files.dropFirst(4) { try? FileManager.default.removeItem(at: old) }
        return dest
    }

    // MARK: Export / Import

    static func exportInteractive(store: LibraryStore) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = fileName()
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await writeBackup(store: store, to: url)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    static func importInteractive(store: LibraryStore) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        if let folder = iCloudFolder, FileManager.default.fileExists(atPath: folder.path) {
            panel.directoryURL = folder
        }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let confirm = NSAlert()
        confirm.messageText = "Sicherung wiederherstellen?"
        confirm.informativeText = "Alle aktuellen Sammlungen und Lieblingsfotos werden durch die Sicherung ersetzt. Der bisherige Stand wird vorher im Papierkorb abgelegt. Polux startet danach neu."
        confirm.addButton(withTitle: "Wiederherstellen")
        confirm.addButton(withTitle: "Abbrechen")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        do {
            try restore(from: url, store: store)
            relaunch()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: Intern

    private static func fileName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm"
        return "Polux-Sicherung_\(f.string(from: Date())).zip"
    }

    private static func writeBackup(store: LibraryStore, to dest: URL) async throws {
        store.saveNow()
        let source = Paths.support
        try? FileManager.default.removeItem(at: dest)
        try await Task.detached(priority: .utility) {
            try run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, dest.path])
        }.value
        AppSettings.shared.lastBackup = Date()
    }

    private static func restore(from zip: URL, store: LibraryStore) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("PoluxRestore-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])

        // library.json suchen (liegt im Ordner „Polux“ der Sicherung)
        guard let e = fm.enumerator(at: work, includingPropertiesForKeys: nil),
              let library = (e.allObjects as? [URL])?.first(where: { $0.lastPathComponent == "library.json" }) else {
            throw BackupError.noLibrary
        }
        // Prüfen, ob die Datei lesbar ist, bevor etwas ersetzt wird.
        guard let data = try? Data(contentsOf: library),
              (try? JSONSerialization.jsonObject(with: data)) != nil else { throw BackupError.invalid }

        let restoredRoot = library.deletingLastPathComponent()
        store.saveNow()
        // Ab jetzt nichts mehr speichern – sonst überschreibt das Beenden die wiederhergestellten Daten.
        store.savingDisabled = true
        let current = Paths.support
        if fm.fileExists(atPath: current.path) {
            try? fm.trashItem(at: current, resultingItemURL: nil)
            if fm.fileExists(atPath: current.path) { try fm.removeItem(at: current) }
        }
        try fm.copyItem(at: restoredRoot, to: current)
    }

    nonisolated private static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw BackupError.tool((tool as NSString).lastPathComponent) }
    }

    /// Startet Polux neu, damit die wiederhergestellten Daten geladen werden.
    private static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"\(path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }
}
