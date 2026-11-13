import SwiftUI
import AppKit

// MARK: - Inhalte je Quelle

struct CredentialSpec {
    let label: String
    let key: CredentialKey
    let secure: Bool
    init(_ label: String, _ key: CredentialKey, _ secure: Bool) {
        self.label = label
        self.key = key
        self.secure = secure
    }
}

struct SourceInfo {
    let summary: String
    let fields: [CredentialSpec]
    let steps: [String]
    let link: String?
    let linkTitle: String?
    let note: String?

    static func of(_ kind: SourceKind) -> SourceInfo {
        switch kind {
        case .openverse:
            return SourceInfo(
                summary: "Bündelt frei lizenzierte Bilder aus Flickr, Wikimedia Commons, Museen und weiteren Sammlungen. Funktioniert ohne Anmeldung. Inhalte für Erwachsene lassen sich pro Sammlung zuschalten.",
                fields: [], steps: [], link: "https://openverse.org", linkTitle: "openverse.org öffnen", note: nil)
        case .artstation:
            return SourceInfo(
                summary: "Digitale Kunst, Concept Art und Illustration. Funktioniert ohne Anmeldung über eine inoffizielle Schnittstelle – sie kann zeitweise blockiert sein.",
                fields: [], steps: [], link: "https://www.artstation.com", linkTitle: "artstation.com öffnen",
                note: "Tipp: Für reine Fotografie in der Sammlung „Nur Fotografien“ aktivieren und ArtStation abschalten.")
        case .rss:
            return SourceInfo(
                summary: "Pinterest bietet keine öffentliche Suche. Öffentliche Boards werden pro Sammlung über ihren RSS-Feed eingebunden. Auch andere Bild-Feeds (z. B. Tumblr, Flickr-Gruppen) funktionieren.",
                fields: [],
                steps: [
                    "Das gewünschte **öffentliche** Board auf pinterest.com im Browser öffnen.",
                    "Die Adresse aus der Adresszeile kopieren, z. B. https://www.pinterest.com/nutzer/boardname/",
                    "Unten bei der passenden Sammlung auf „Boards bearbeiten“ klicken und die Adresse einfügen.",
                    "Mit „Testen“ prüfen, ob Bilder gefunden werden."
                ],
                link: "https://www.pinterest.com", linkTitle: "pinterest.com öffnen", note: nil)
        case .unsplash:
            return SourceInfo(
                summary: "Kuratierte, hochwertige Fotografie. Akt wird von Unsplash weitgehend ausgefiltert. Der kostenlose Zugang erlaubt rund 50 Anfragen pro Stunde – für Polux mehr als genug.",
                fields: [CredentialSpec("Access Key", .unsplash, true)],
                steps: [
                    "Auf unsplash.com/developers anmelden bzw. ein kostenloses Konto anlegen.",
                    "„New Application“ wählen, die Richtlinien bestätigen und als Namen z. B. „Polux“ eintragen.",
                    "In der App-Übersicht unter „Keys“ den **Access Key** kopieren (nicht den Secret Key) und oben einfügen."
                ],
                link: "https://unsplash.com/oauth/applications", linkTitle: "Unsplash-Entwicklerseite öffnen", note: nil)
        case .flickr:
            return SourceInfo(
                summary: "Riesiges Fotoarchiv – auch Bilder, die nicht frei lizenziert sind. Ergänzt Openverse um viele aktuelle Arbeiten.",
                fields: [CredentialSpec("API Key", .flickr, true)],
                steps: [
                    "Auf flickr.com anmelden und die Seite „Create an App“ öffnen.",
                    "„Apply for a Non-Commercial Key“ wählen.",
                    "Name (z. B. „Polux“) und kurze Beschreibung eintragen, Bedingungen bestätigen.",
                    "Den angezeigten **Key** kopieren (nicht das Secret) und oben einfügen."
                ],
                link: "https://www.flickr.com/services/apps/create/", linkTitle: "Flickr-Schlüssel beantragen",
                note: "Inhalte mit Einschränkung (z. B. Akt) liefert Flickr ohne Benutzer-Login nur begrenzt – Openverse ergänzt hier.")
        case .pexels:
            return SourceInfo(
                summary: "Stockfotografie mit guten Licht- und Farbstimmungen. Keine Aktdarstellungen.",
                fields: [CredentialSpec("API Key", .pexels, true)],
                steps: [
                    "Auf pexels.com/api ein kostenloses Konto anlegen bzw. anmelden.",
                    "Das kurze Formular zum Verwendungszweck ausfüllen (z. B. „Private Inspirations-App“).",
                    "Den angezeigten **API Key** kopieren und oben einfügen."
                ],
                link: "https://www.pexels.com/api/", linkTitle: "Pexels-API öffnen", note: nil)
        case .deviantart:
            return SourceInfo(
                summary: "Kunst- und Fotocommunity – gut für düstere Inszenierungen, Fine-Art und Akt. Benötigt eine kostenlose App-Registrierung (Client ID + Secret).",
                fields: [CredentialSpec("Client ID", .deviantartID, false), CredentialSpec("Client Secret", .deviantartSecret, true)],
                steps: [
                    "Auf deviantart.com anmelden und die Entwicklerseite öffnen.",
                    "„Register your Application“ wählen und einen Namen eintragen.",
                    "Bei „OAuth2 Redirect URI Whitelist“ z. B. https://localhost eintragen (wird von Polux nicht genutzt, ist aber Pflicht).",
                    "Speichern und anschließend **client_id** und **client_secret** kopieren und oben einfügen."
                ],
                link: "https://www.deviantart.com/developers/apps", linkTitle: "DeviantArt-Apps verwalten", note: nil)
        }
    }
}

// MARK: - Übersicht „Zugänge & Quellen“

extension SourceKind {
    /// Kurzbeschreibung für die Kachel.
    var tagline: String {
        switch self {
        case .openverse: return "Flickr CC, Wikimedia & Museen · Akt möglich"
        case .artstation: return "Digitale Kunst & Concept Art"
        case .rss: return "Eigene öffentliche Boards je Sammlung"
        case .unsplash: return "Kuratierte Fotografie · kaum Akt"
        case .flickr: return "Riesiges Fotoarchiv"
        case .pexels: return "Stockfotos · keine Akte"
        case .deviantart: return "Kunst & Fotografie · düster, Akt"
        }
    }
}

struct SourcesOverviewView: View {
    @ObservedObject private var tester = ConnectionTester.shared
    @EnvironmentObject var store: LibraryStore
    @State private var testingAll = false

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    PageHeader(icon: "key.horizontal", title: "Zugänge & Quellen",
                               subtitle: "Woher Polux die Fotos holt. Quellen ohne Anmeldung laufen sofort – für die anderen trägst du einmalig einen kostenlosen Schlüssel ein.")
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 6) {
                        Button {
                            testingAll = true
                            Task { @MainActor in
                                for k in SourceKind.menuOrder where k != .rss && Providers.hasCredentials(k) {
                                    await tester.test(k)
                                }
                                testingAll = false
                            }
                        } label: {
                            Label("Alle testen", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(testingAll)
                        if testingAll { ProgressView().controlSize(.small) }
                    }
                }

                group("Sofort nutzbar – ohne Anmeldung", [.openverse, .artstation, .rss])
                group("Mit kostenlosem Zugang", [.unsplash, .flickr, .pexels, .deviantart])

                Text("Behance bietet keine öffentliche Schnittstelle mehr und kann daher nicht eingebunden werden. Welche Quelle eine Sammlung nutzt, stellst du in der Sammlung unter „Quellen“ ein.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(24)
        }
    }

    private func group(_ title: String, _ kinds: [SourceKind]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.8)
                .foregroundColor(.secondary)
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(kinds) { SourceCard(kind: $0) }
            }
        }
    }
}

/// Kachel einer Bildquelle mit Status und „Einrichten“.
struct SourceCard: View {
    let kind: SourceKind
    @ObservedObject private var tester = ConnectionTester.shared
    @EnvironmentObject var store: LibraryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: kind.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black))
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title).font(.headline)
                    Text(kind.tagline).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            HStack {
                StatusPill(kind: kind)
                Spacer()
                Button(buttonTitle) { SettingsNavigation.shared.setUp(kind) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.08)))
    }

    private var buttonTitle: String {
        if kind == .rss { return "Anleitung" }
        if kind.needsCredentials && !Providers.hasCredentials(kind) { return "Einrichten …" }
        return "Details"
    }
}

/// Kompakte Statusanzeige als Kapsel.
struct StatusPill: View {
    let kind: SourceKind
    @ObservedObject private var tester = ConnectionTester.shared
    @EnvironmentObject var store: LibraryStore

    var body: some View {
        let (text, color, icon) = describe()
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
            .lineLimit(1)
    }

    private func describe() -> (String, Color, String) {
        if kind == .rss {
            let boards = store.collections.reduce(0) { $0 + $1.feeds.count }
            return boards == 0 ? ("Keine Boards", .secondary, "pin.slash")
                               : ("\(boards) Board\(boards == 1 ? "" : "s")", .green, "pin.fill")
        }
        switch tester.status(kind) {
        case .ok: return ("Verbunden", .green, "checkmark.circle.fill")
        case .failed: return ("Fehler", .red, "exclamationmark.triangle.fill")
        case .missing: return ("Schlüssel fehlt", .orange, "key")
        case .testing: return ("Teste …", .secondary, "circle.dotted")
        case .unknown: return (kind.needsCredentials ? "Eingerichtet" : "Bereit", .secondary, "circle")
        }
    }
}

/// Fenster zum Einrichten einer Quelle (Schlüssel, Test, Anleitung).
struct SourceSetupSheet: View {
    let kind: SourceKind
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SourceDetailView(kind: kind)
            Divider()
            HStack {
                Spacer()
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 600, height: 640)
    }
}

// MARK: - Detailseite je Quelle

struct SourceDetailView: View {
    let kind: SourceKind
    @EnvironmentObject var store: LibraryStore

    var body: some View {
        let info = SourceInfo.of(kind)
        Form {
            Section {
                PageHeader(icon: kind.icon, title: kind.title, subtitle: info.summary)
            }

            if !info.fields.isEmpty {
                Section("Zugang") {
                    ForEach(info.fields, id: \.key) { f in
                        CredentialField(label: f.label, key: f.key, kind: kind, secure: f.secure)
                    }
                }
            }

            if kind != .rss {
                Section("Verbindung") {
                    ConnectionRow(kind: kind)
                }
            }

            if !info.steps.isEmpty {
                Section(kind == .rss ? "So bindest du ein Board ein" : "So bekommst du den Schlüssel") {
                    GuideSteps(steps: info.steps)
                }
            }

            if kind == .rss {
                Section("Boards je Sammlung") {
                    ForEach(store.collections) { c in
                        HStack {
                            Text(c.name)
                            Spacer()
                            Text(c.feeds.isEmpty ? "keine Boards" : "\(c.feeds.count) Board\(c.feeds.count == 1 ? "" : "s")")
                                .foregroundColor(.secondary)
                            Button("Boards bearbeiten") {
                                SettingsNavigation.shared.setupSource = nil
                                SettingsNavigation.shared.openCollection(c.id, tab: .sources)
                            }
                        }
                    }
                }
            } else {
                Section("Verwendet in Sammlungen") {
                    ForEach(store.collections) { c in
                        Toggle(c.name, isOn: Binding(
                            get: { store.collection(c.id)?.sources.contains(kind) ?? false },
                            set: { on in
                                guard var v = store.collection(c.id) else { return }
                                if on { v.sources.insert(kind) } else { v.sources.remove(kind) }
                                store.update(v)
                            }
                        ))
                    }
                }
            }

            if info.link != nil || info.note != nil {
                Section {
                    if let link = info.link, let url = URL(string: link) {
                        Link((info.linkTitle ?? link) + " ↗", destination: url)
                    }
                    if let note = info.note {
                        Text(note).font(.callout).foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if kind != .rss, Providers.hasCredentials(kind), ConnectionTester.shared.status(kind) == .unknown,
               !PreviewRenderer.isRendering {
                Task { @MainActor in await ConnectionTester.shared.test(kind) }
            }
        }
    }
}

/// Eingabefeld für einen Schlüssel – speichert in den Schlüsselbund, Enter testet sofort.
struct CredentialField: View {
    let label: String
    let key: CredentialKey
    let kind: SourceKind
    var secure = true

    @State private var value = ""
    @State private var loaded = false
    @State private var reveal = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if secure && !reveal {
                    SecureField(label, text: $value)
                } else {
                    TextField(label, text: $value)
                }
            }
            .onSubmit { Task { @MainActor in await ConnectionTester.shared.test(kind) } }

            if secure {
                Button { reveal.toggle() } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(reveal ? "Verbergen" : "Anzeigen")
            }
            Button {
                if let s = NSPasteboard.general.string(forType: .string) {
                    value = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        await ConnectionTester.shared.test(kind)
                    }
                }
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(.borderless)
            .help("Aus der Zwischenablage einfügen und testen")
        }
        .onAppear {
            value = Keychain.get(key) ?? ""
            DispatchQueue.main.async { loaded = true }
        }
        .onChange(of: value) { v in
            guard loaded else { return }
            Keychain.set(v, for: key)
            ConnectionTester.shared.invalidate(kind)
        }
    }
}

/// Nummerierte Schritt-für-Schritt-Anleitung.
struct GuideSteps: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(i + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.black))
                    Text(LocalizedStringKey(step))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct ConnectionRow: View {
    let kind: SourceKind
    var title: String? = nil
    @ObservedObject private var tester = ConnectionTester.shared

    var body: some View {
        let status = tester.status(kind)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let title {
                Text(title).frame(minWidth: 90, alignment: .leading)
            }
            icon(status)
            Text(text(status))
                .font(.callout)
                .foregroundColor(color(status))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if status == .testing {
                ProgressView().controlSize(.small)
            }
            Button("Verbindung testen") { Task { await tester.test(kind) } }
                .disabled(status == .testing || status == .missing)
        }
    }

    @ViewBuilder
    private func icon(_ s: ConnectionTester.Status) -> some View {
        switch s {
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
        case .missing: Image(systemName: "key").foregroundColor(.secondary)
        case .testing, .unknown: Image(systemName: "circle.dotted").foregroundColor(.secondary)
        }
    }

    private func text(_ s: ConnectionTester.Status) -> String {
        switch s {
        case .ok(let m): return m
        case .failed(let m): return m
        case .missing: return "Noch kein Schlüssel eingetragen"
        case .testing: return "Teste Verbindung …"
        case .unknown: return "Noch nicht getestet"
        }
    }

    private func color(_ s: ConnectionTester.Status) -> Color {
        switch s {
        case .ok: return .green
        case .failed: return .red
        default: return .secondary
        }
    }
}

/// Aufklappbare Kurzanleitung zum Schlüssel.

struct SourceStatusBadge: View {
    let kind: SourceKind
    @ObservedObject private var tester = ConnectionTester.shared

    var body: some View {
        switch tester.status(kind) {
        case .ok:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green).help("Verbunden")
        case .failed(let m):
            Button {
                SettingsNavigation.shared.setUp(kind)
            } label: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help(m)
        default:
            EmptyView()
        }
    }
}

/// Testet ein einzelnes Pinterest-Board bzw. einen RSS-Feed.
struct FeedTestButton: View {
    let feed: String
    @State private var status: ConnectionTester.Status = .unknown

    var body: some View {
        HStack(spacing: 6) {
            switch status {
            case .testing:
                ProgressView().controlSize(.small)
            case .ok(let m):
                Label(m, systemImage: "checkmark.circle.fill").foregroundColor(.green).font(.caption)
            case .failed(let m):
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red).help(m)
                Text(m).font(.caption).foregroundColor(.red).lineLimit(2)
            default:
                EmptyView()
            }
            Button("Testen") {
                status = .testing
                Task { status = await ConnectionTester.testFeed(feed) }
            }
            .disabled(status == .testing)
        }
    }
}
