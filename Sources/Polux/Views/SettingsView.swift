import SwiftUI
import AppKit

/// Menüpunkte der Einstellungen.
enum SettingsPage: Hashable {
    case collection(UUID)
    case sourcesOverview
    case source(SourceKind)
    case playback
    case widget
    case storage
    case updates
}

final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var page: SettingsPage? = .playback

    func open(_ tab: SettingsTab, currentCollection: UUID) {
        switch tab {
        case .collections: page = .collection(currentCollection)
        case .sources: page = .sourcesOverview
        case .general: page = .playback
        case .updates: page = .updates
        }
    }
}

extension SourceKind {
    var title: String {
        switch self {
        case .openverse: return "Openverse"
        case .unsplash: return "Unsplash"
        case .flickr: return "Flickr"
        case .pexels: return "Pexels"
        case .deviantart: return "DeviantArt"
        case .artstation: return "ArtStation"
        case .rss: return "Pinterest & Feeds"
        }
    }

    var icon: String {
        switch self {
        case .openverse: return "globe"
        case .unsplash: return "camera"
        case .flickr: return "camera.aperture"
        case .pexels: return "photo"
        case .deviantart: return "theatermasks"
        case .artstation: return "paintpalette"
        case .rss: return "pin"
        }
    }

    /// Reihenfolge in Menü und Übersicht: zuerst ohne Anmeldung.
    static var menuOrder: [SourceKind] { [.openverse, .artstation, .rss, .unsplash, .flickr, .pexels, .deviantart] }
}

// MARK: - Fenster mit Seitenleiste

struct SettingsView: View {
    @ObservedObject var nav = SettingsNavigation.shared
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var updater: UpdateChecker

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
        } detail: {
            detail
                .id(nav.page)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, minHeight: 600)
    }

    private var sidebar: some View {
        List(selection: $nav.page) {
            Section("Sammlungen") {
                ForEach(store.collections) { c in
                    HStack {
                        Label(c.name, systemImage: "rectangle.stack")
                            .lineLimit(1)
                        Spacer()
                        if c.id == store.currentCollectionID {
                            Image(systemName: "eye")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .help("Wird gerade im Polaroid angezeigt")
                        }
                    }
                    .tag(SettingsPage.collection(c.id))
                    .contextMenu {
                        Button("Im Polaroid anzeigen") { store.currentCollectionID = c.id }
                        Button("Galerie öffnen") { Router.shared.openGallery(c.id) }
                    }
                }
                .onMove { store.moveCollections(from: $0, to: $1) }

                Button {
                    let id = store.addCollection(name: "Neue Sammlung")
                    nav.page = .collection(id)
                } label: {
                    Label("Neue Sammlung", systemImage: "plus")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }

            Section("Bildquellen") {
                Label("Übersicht", systemImage: "list.bullet.rectangle")
                    .tag(SettingsPage.sourcesOverview)
                ForEach(SourceKind.menuOrder) { kind in
                    HStack {
                        Label(kind.title, systemImage: kind.icon)
                        Spacer()
                        StatusDot(kind: kind)
                    }
                    .tag(SettingsPage.source(kind))
                }
            }

            Section("App") {
                Label("Wiedergabe", systemImage: "play.circle")
                    .tag(SettingsPage.playback)
                Label("Widget & Start", systemImage: "rectangle.on.rectangle")
                    .tag(SettingsPage.widget)
                Label("Speicher", systemImage: "internaldrive")
                    .tag(SettingsPage.storage)
                HStack {
                    Label("Updates", systemImage: "arrow.down.circle")
                    Spacer()
                    if updater.availableVersion != nil {
                        Circle().fill(Color.orange).frame(width: 7, height: 7)
                    }
                }
                .tag(SettingsPage.updates)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detail: some View {
        switch nav.page {
        case .collection(let id) where store.collection(id) != nil:
            CollectionEditor(collectionID: id)
        case .sourcesOverview:
            SourcesOverviewView()
        case .source(let kind):
            SourceDetailView(kind: kind)
        case .playback:
            PlaybackSettingsView()
        case .widget:
            WidgetSettingsView()
        case .storage:
            StorageSettingsView()
        case .updates:
            UpdatesSettingsView()
        default:
            VStack(spacing: 8) {
                Image(systemName: "sidebar.left").font(.system(size: 28)).foregroundColor(.secondary)
                Text("Links einen Menüpunkt wählen").foregroundColor(.secondary)
            }
        }
    }
}

/// Überschrift jeder Einstellungsseite.
struct PageHeader: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 20, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Farbpunkt für den Verbindungsstatus in der Seitenleiste.
struct StatusDot: View {
    let kind: SourceKind
    @ObservedObject private var tester = ConnectionTester.shared
    @EnvironmentObject var store: LibraryStore

    var body: some View {
        let color: Color? = {
            if kind == .rss {
                return store.collections.contains { !$0.feeds.isEmpty } ? .green : nil
            }
            switch tester.status(kind) {
            case .ok: return .green
            case .failed: return .red
            default: return nil
            }
        }()
        if let color {
            Circle().fill(color).frame(width: 7, height: 7)
        } else if kind.needsCredentials && !Providers.hasCredentials(kind) {
            Image(systemName: "key").font(.caption2).foregroundColor(.secondary).help("Schlüssel fehlt")
        }
    }
}

// MARK: - App: Wiedergabe

struct PlaybackSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var engine: InspirationEngine

    var body: some View {
        Form {
            Section {
                PageHeader(icon: "play.circle", title: "Wiedergabe",
                           subtitle: "Wie oft Polux ein neues Foto zeigt.")
            }
            Section("Bildwechsel") {
                Stepper(value: $settings.intervalMinutes, in: 1...240) {
                    Text("Neues Foto alle **\(settings.intervalMinutes) Minuten**")
                }
                Picker("Schnellauswahl", selection: $settings.intervalMinutes) {
                    Text("1 Min.").tag(1)
                    Text("5 Min.").tag(5)
                    Text("15 Min.").tag(15)
                    Text("30 Min.").tag(30)
                    Text("1 Std.").tag(60)
                }
                .pickerStyle(.segmented)
            }
            Section("Steuerung") {
                Toggle("Pausiert", isOn: $settings.isPaused)
                Button("Jetzt nächstes Foto zeigen") { engine.next() }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - App: Widget & Start

struct WidgetSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
                PageHeader(icon: "rectangle.on.rectangle", title: "Widget & Start",
                           subtitle: "Aussehen und Verhalten des Polaroids auf dem Schreibtisch.")
            }
            Section("Darstellung") {
                Picker("Größe", selection: $settings.polaroidSize) {
                    ForEach(PolaroidSize.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Fensterebene", selection: $settings.windowLevel) {
                    ForEach(WidgetLevel.allCases) { Text($0.label).tag($0) }
                }
                Button("Polaroid-Position zurücksetzen") { Router.shared.resetPosition() }
            }
            Section("Start") {
                Toggle("Beim Anmelden automatisch starten", isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        LaunchAtLogin.set(on)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                ))
                Text("Beenden: x oben rechts im Polaroid oder Kamera-Symbol in der Menüleiste → „Polux beenden“.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }
}

// MARK: - App: Speicher

struct StorageSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var engine: InspirationEngine
    @State private var cacheSize: Int64 = 0

    var body: some View {
        Form {
            Section {
                PageHeader(icon: "internaldrive", title: "Speicher",
                           subtitle: "Likes werden als kompakte HEIC-Vorschau plus Link gespeichert. Die Originalgröße lädt Polux bei Bedarf aus dem Netz.")
            }
            Section("Lieblingsfotos") {
                Picker("Gespeicherte Größe", selection: $settings.thumbnailMaxPixel) {
                    Text("Klein · 600 px (ca. 30–50 KB)").tag(600)
                    Text("Mittel · 900 px (ca. 60–100 KB)").tag(900)
                    Text("Groß · 1400 px (ca. 150–250 KB)").tag(1400)
                }
                LabeledContent("Belegt", value: Paths.formatBytes(store.totalLikeBytes))
                ForEach(store.collections) { c in
                    LabeledContent(c.name, value: "\(c.likes.count) Fotos · \(Paths.formatBytes(Int64(c.totalBytes)))")
                        .foregroundColor(.secondary)
                }
            }
            Section("Verlauf") {
                LabeledContent("Verlaufs-Cache (max. 24 Fotos)", value: Paths.formatBytes(cacheSize))
                Button("Verlaufs-Cache leeren") {
                    engine.clearHistoryCache()
                    cacheSize = Paths.directorySize(Paths.history)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { cacheSize = Paths.directorySize(Paths.history) }
    }
}

// MARK: - App: Updates

struct UpdatesSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var updater: UpdateChecker

    var body: some View {
        Form {
            Section {
                PageHeader(icon: "arrow.down.circle", title: "Updates",
                           subtitle: "Polux prüft neue Versionen auf GitHub.")
            }
            Section {
                LabeledContent("Installierte Version", value: AppInfo.version)
                Toggle("Automatisch einmal täglich prüfen", isOn: $settings.autoCheckUpdates)
                HStack {
                    Button("Jetzt nach Updates suchen") { Task { await updater.check() } }
                        .disabled(updater.state == .checking)
                    if updater.state == .checking { ProgressView().controlSize(.small) }
                }
                statusView
                if let last = settings.lastUpdateCheck {
                    LabeledContent("Zuletzt geprüft", value: last.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var statusView: some View {
        switch updater.state {
        case .idle, .checking:
            EmptyView()
        case .upToDate:
            Label("Polux ist auf dem neuesten Stand.", systemImage: "checkmark.seal")
                .foregroundColor(.green)
        case .available(let version, let url):
            VStack(alignment: .leading, spacing: 8) {
                Label("Version \(version) ist verfügbar.", systemImage: "arrow.down.circle.fill")
                    .foregroundColor(.orange)
                Button("Herunterladen") { NSWorkspace.shared.open(url) }
                Text("Nach dem Download die neue Polux.app in den Programme-Ordner ziehen und die alte ersetzen.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundColor(.secondary)
        }
    }
}
