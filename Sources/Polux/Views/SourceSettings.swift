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
                    "Unten bei der passenden Sammlung auf „Bearbeiten“ klicken und die Adresse unter „Pinterest-Boards & RSS-Feeds“ einfügen.",
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

// MARK: - Übersicht

struct SourcesOverviewView: View {
    @ObservedObject private var tester = ConnectionTester.shared
    @State private var testingAll = false

    var body: some View {
        Form {
            Section {
                PageHeader(icon: "list.bullet.rectangle", title: "Bildquellen",
                           subtitle: "Openverse und ArtStation funktionieren sofort. Für weitere Quellen trägst du einmalig einen kostenlosen Schlüssel ein – Schlüssel werden im macOS-Schlüsselbund gespeichert.")
            }
            Section("Ohne Anmeldung") {
                ForEach([SourceKind.openverse, .artstation]) { row($0) }
                pinterestRow
            }
            Section("Mit kostenlosem Schlüssel") {
                ForEach([SourceKind.unsplash, .flickr, .pexels, .deviantart]) { row($0) }
            }
            Section {
                HStack {
                    Button("Alle Verbindungen testen") {
                        testingAll = true
                        Task { @MainActor in
                            for k in SourceKind.menuOrder where k != .rss && Providers.hasCredentials(k) {
                                await tester.test(k)
                            }
                            testingAll = false
                        }
                    }
                    .disabled(testingAll)
                    if testingAll { ProgressView().controlSize(.small) }
                }
            } footer: {
                Text("Behance bietet keine öffentliche Schnittstelle mehr und kann daher nicht eingebunden werden.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ kind: SourceKind) -> some View {
        HStack(spacing: 10) {
            Image(systemName: kind.icon).frame(width: 20).foregroundColor(.secondary)
            ConnectionRow(kind: kind, title: kind.title)
            Button {
                SettingsNavigation.shared.page = .source(kind)
            } label: { Image(systemName: "chevron.right") }
            .buttonStyle(.borderless)
            .help("Einrichten")
        }
    }

    private var pinterestRow: some View {
        HStack(spacing: 10) {
            Image(systemName: SourceKind.rss.icon).frame(width: 20).foregroundColor(.secondary)
            Text(SourceKind.rss.title).frame(minWidth: 90, alignment: .leading)
            Text("Boards werden pro Sammlung eingetragen")
                .font(.callout).foregroundColor(.secondary)
            Spacer()
            Button {
                SettingsNavigation.shared.page = .source(.rss)
            } label: { Image(systemName: "chevron.right") }
            .buttonStyle(.borderless)
        }
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
                            Button("Bearbeiten") { SettingsNavigation.shared.page = .collection(c.id) }
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
                SettingsNavigation.shared.page = .source(kind)
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
