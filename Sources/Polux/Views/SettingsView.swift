import SwiftUI
import AppKit

final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var tab: SettingsTab = .collections
}

struct SettingsView: View {
    @ObservedObject var nav = SettingsNavigation.shared

    var body: some View {
        TabView(selection: $nav.tab) {
            CollectionsSettingsView()
                .tabItem { Label("Sammlungen", systemImage: "rectangle.stack") }
                .tag(SettingsTab.collections)
            SourcesSettingsView()
                .tabItem { Label("Quellen", systemImage: "globe") }
                .tag(SettingsTab.sources)
            GeneralSettingsView()
                .tabItem { Label("Allgemein", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            UpdatesSettingsView()
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
                .tag(SettingsTab.updates)
        }
        .padding(.top, 8)
        .frame(minWidth: 780, minHeight: 580)
    }
}

// MARK: - Sammlungen

struct CollectionsSettingsView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var selection: UUID?
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.collections) { c in
                        HStack {
                            Text(c.name).lineLimit(1)
                            Spacer()
                            if c.id == store.currentCollectionID {
                                Image(systemName: "photo").foregroundColor(.secondary).help("Wird gerade angezeigt")
                            }
                        }
                    }
                    .onMove { store.moveCollections(from: $0, to: $1) }
                }
                .listStyle(.sidebar)

                Divider()
                HStack(spacing: 2) {
                    Button {
                        selection = store.addCollection(name: "Neue Sammlung")
                    } label: { Image(systemName: "plus").frame(width: 22, height: 20) }
                    .help("Sammlung hinzufügen")
                    Button {
                        confirmDelete = true
                    } label: { Image(systemName: "minus").frame(width: 22, height: 20) }
                    .disabled(selection == nil || store.collections.count <= 1)
                    .help("Sammlung löschen")
                    Spacer()
                    Text("Ziehen zum Sortieren")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 220)

            Divider()

            if let id = selection, store.collection(id) != nil {
                CollectionEditor(collectionID: id)
                    .id(id)
            } else {
                VStack {
                    Spacer()
                    Text("Sammlung auswählen").foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { if selection == nil { selection = store.currentCollectionID } }
        .alert("Sammlung löschen?", isPresented: $confirmDelete) {
            Button("Löschen", role: .destructive) {
                if let id = selection {
                    store.deleteCollection(id)
                    selection = store.currentCollectionID
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die Sammlung und alle gelikten Fotos darin werden entfernt.")
        }
    }
}

struct CollectionEditor: View {
    let collectionID: UUID
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var engine: InspirationEngine
    @State private var newFeed = ""

    private var binding: Binding<PhotoCollection> {
        Binding(
            get: { store.collection(collectionID) ?? PhotoCollection(name: "") },
            set: { store.update($0) }
        )
    }

    var body: some View {
        let c = binding
        let learned = StyleEngine.termProfile(for: c.wrappedValue).learned

        Form {
            Section {
                TextField("Name", text: c.name)
                HStack {
                    Button("Im Polaroid anzeigen") { engine.switchCollection(to: collectionID) }
                        .disabled(store.currentCollectionID == collectionID)
                    Button("Galerie öffnen") { Router.shared.openGallery(collectionID) }
                }
            }

            Section("Wonach suchen?") {
                TokenEditor(title: "Schlagwörter (Englisch liefert die meisten Treffer)",
                            tokens: c.keywords,
                            placeholder: "z. B. low key portrait, Enter zum Hinzufügen")
                TokenEditor(title: "Ausschließen",
                            tokens: c.excludedWords,
                            placeholder: "z. B. wedding, selfie")
                Toggle("Aktfotografie & Mature-Inhalte zulassen", isOn: c.allowNudity)
                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: c.darkBias, in: 0...1) {
                        Text("Düstere Inszenierung")
                    } minimumValueLabel: {
                        Image(systemName: "sun.max")
                    } maximumValueLabel: {
                        Image(systemName: "moon.fill")
                    }
                    Text("Bevorzugt Low-Key, dunkle Tonwerte und dramatisches Licht.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Toggle("Nur Fotografien (keine Illustrationen)", isOn: c.photosOnly)
            }

            Section("Quellen") {
                ForEach(SourceKind.allCases) { kind in
                    Toggle(isOn: Binding(
                        get: { c.wrappedValue.sources.contains(kind) },
                        set: { on in
                            var v = c.wrappedValue
                            if on { v.sources.insert(kind) } else { v.sources.remove(kind) }
                            c.wrappedValue = v
                        }
                    )) {
                        HStack {
                            Text(kind.displayName)
                            if kind.needsCredentials && !Providers.hasCredentials(kind) {
                                Button("Schlüssel fehlt") { Router.shared.openSettings(.sources) }
                                    .buttonStyle(.link)
                                    .font(.caption)
                            }
                            if kind == .rss && c.wrappedValue.feeds.isEmpty {
                                Text("Feed unten eintragen").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                ForEach(c.wrappedValue.feeds, id: \.self) { feed in
                    HStack {
                        Text(feed).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button {
                            var v = c.wrappedValue
                            v.feeds.removeAll { $0 == feed }
                            c.wrappedValue = v
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("https://www.pinterest.com/nutzer/board/", text: $newFeed)
                        .onSubmit(addFeed)
                    Button("Hinzufügen", action: addFeed)
                        .disabled(newFeed.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Pinterest-Boards & RSS-Feeds")
            } footer: {
                Text("Öffentliche Pinterest-Boards werden über ihren RSS-Feed eingebunden. Auch andere Bild-Feeds (z. B. Tumblr, Flickr-Gruppen) funktionieren.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Gelernter Stil") {
                if learned.isEmpty {
                    Text("Noch nichts gelernt – like Fotos im Polaroid, dann erweitert Polux die Suche automatisch um passende Stilbegriffe.")
                        .foregroundColor(.secondary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(learned, id: \.self) { Chip(text: $0) }
                    }
                }
                LabeledContent("Lieblingsfotos",
                               value: "\(c.wrappedValue.likes.count) · \(Paths.formatBytes(Int64(c.wrappedValue.totalBytes)))")
                LabeledContent("Aus der Galerie entfernt (Negativ-Signale)",
                               value: "\(c.wrappedValue.rejectedPrints.count)")
                Button("Negativ-Signale zurücksetzen") { store.resetRejections(collectionID) }
                    .disabled(c.wrappedValue.rejectedTags.isEmpty && c.wrappedValue.rejectedPrints.isEmpty)
            }
        }
        .formStyle(.grouped)
    }

    private func addFeed() {
        let f = newFeed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty, RSSProvider.normalizedFeedURL(f) != nil else { return }
        var v = binding.wrappedValue
        if !v.feeds.contains(f) { v.feeds.append(f) }
        v.sources.insert(.rss)
        binding.wrappedValue = v
        newFeed = ""
    }
}

// MARK: - Quellen / API-Schlüssel

struct SourcesSettingsView: View {
    @State private var unsplash = ""
    @State private var flickr = ""
    @State private var pexels = ""
    @State private var daID = ""
    @State private var daSecret = ""
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                Text("Openverse (bündelt u. a. Flickr Creative Commons und Wikimedia Commons), ArtStation sowie Pinterest-Boards per RSS funktionieren ohne Anmeldung. Für weitere Quellen trägst du kostenlose Entwickler-Schlüssel ein – sie werden im macOS-Schlüsselbund gespeichert.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            Section("Unsplash") {
                SecureField("Access Key", text: $unsplash)
                Link("Schlüssel erstellen: unsplash.com/developers", destination: URL(string: "https://unsplash.com/developers")!)
            }
            Section("Flickr") {
                SecureField("API Key", text: $flickr)
                Link("Schlüssel erstellen: flickr.com/services/apps/create", destination: URL(string: "https://www.flickr.com/services/apps/create/")!)
                Text("Hinweis: Flickr liefert Inhalte mit Einschränkung (z. B. Akt) ohne Benutzer-Login nur begrenzt. Openverse ergänzt hier.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("Pexels") {
                SecureField("API Key", text: $pexels)
                Link("Schlüssel erstellen: pexels.com/api", destination: URL(string: "https://www.pexels.com/api/")!)
            }
            Section("DeviantArt") {
                TextField("Client ID", text: $daID)
                SecureField("Client Secret", text: $daSecret)
                Link("App registrieren: deviantart.com/developers", destination: URL(string: "https://www.deviantart.com/developers/")!)
            }
            Section("Pinterest & Behance") {
                Text("Pinterest und Behance bieten keine öffentliche Such-Schnittstelle. Pinterest-Boards bindest du pro Sammlung als RSS-Feed ein (Reiter „Sammlungen“). ArtStation nutzt eine inoffizielle Schnittstelle und kann zeitweise ausfallen.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            unsplash = Keychain.get(.unsplash) ?? ""
            flickr = Keychain.get(.flickr) ?? ""
            pexels = Keychain.get(.pexels) ?? ""
            daID = Keychain.get(.deviantartID) ?? ""
            daSecret = Keychain.get(.deviantartSecret) ?? ""
            DispatchQueue.main.async { loaded = true }
        }
        .onChange(of: unsplash) { if loaded { Keychain.set($0, for: .unsplash) } }
        .onChange(of: flickr) { if loaded { Keychain.set($0, for: .flickr) } }
        .onChange(of: pexels) { if loaded { Keychain.set($0, for: .pexels) } }
        .onChange(of: daID) { if loaded { Keychain.set($0, for: .deviantartID) } }
        .onChange(of: daSecret) { if loaded { Keychain.set($0, for: .deviantartSecret) } }
    }
}

// MARK: - Allgemein

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var engine: InspirationEngine
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var cacheSize: Int64 = 0

    var body: some View {
        Form {
            Section("Wiedergabe") {
                Stepper(value: $settings.intervalMinutes, in: 1...240) {
                    Text("Neues Foto alle \(settings.intervalMinutes) Minuten")
                }
                Toggle("Pausiert", isOn: $settings.isPaused)
            }

            Section("Widget") {
                Picker("Fensterebene", selection: $settings.windowLevel) {
                    ForEach(WidgetLevel.allCases) { Text($0.label).tag($0) }
                }
                Picker("Größe", selection: $settings.polaroidSize) {
                    ForEach(PolaroidSize.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Beim Anmelden automatisch starten", isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        LaunchAtLogin.set(on)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                ))
                Button("Polaroid-Position zurücksetzen") { Router.shared.resetPosition() }
            }

            Section {
                Picker("Gespeicherte Größe gelikter Fotos", selection: $settings.thumbnailMaxPixel) {
                    Text("Klein · 600 px (ca. 30–50 KB)").tag(600)
                    Text("Mittel · 900 px (ca. 60–100 KB)").tag(900)
                    Text("Groß · 1400 px (ca. 150–250 KB)").tag(1400)
                }
                LabeledContent("Lieblingsfotos gesamt", value: Paths.formatBytes(store.totalLikeBytes))
                LabeledContent("Verlaufs-Cache (max. 24 Fotos)", value: Paths.formatBytes(cacheSize))
                Button("Verlaufs-Cache leeren") {
                    engine.clearHistoryCache()
                    cacheSize = Paths.directorySize(Paths.history)
                }
            } header: {
                Text("Speicher")
            } footer: {
                Text("Likes werden als kompakte HEIC-Vorschau plus Link gespeichert. Die Originalgröße lädt Polux bei Bedarf aus dem Netz.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
            cacheSize = Paths.directorySize(Paths.history)
        }
    }
}

// MARK: - Updates

struct UpdatesSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var updater: UpdateChecker

    var body: some View {
        Form {
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
