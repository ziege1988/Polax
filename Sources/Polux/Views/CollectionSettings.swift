import SwiftUI
import AppKit

// MARK: - Sammlung bearbeiten (Reiter: Suche · Quellen · Stil & Fotos)

struct CollectionEditor: View {
    let collectionID: UUID
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var engine: InspirationEngine
    @ObservedObject private var nav = SettingsNavigation.shared

    private var binding: Binding<PhotoCollection> {
        Binding(
            get: { store.collection(collectionID) ?? PhotoCollection(name: "") },
            set: { store.update($0) }
        )
    }

    var body: some View {
        let c = binding.wrappedValue
        VStack(spacing: 0) {
            // Kopf mit Name, Kennzahlen und Schnellaktionen
            HStack(alignment: .center, spacing: 12) {
                PageHeader(icon: "rectangle.stack", title: c.name.isEmpty ? "Sammlung" : c.name,
                           subtitle: "\(c.likes.count) Lieblingsfotos · \(Paths.formatBytes(Int64(c.totalBytes))) · \(c.keywords.count) Schlagwörter")
                Spacer(minLength: 8)
                if store.currentCollectionID == collectionID {
                    Label("Im Polaroid", systemImage: "eye")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Button("Im Polaroid anzeigen") { engine.switchCollection(to: collectionID) }
                }
                Button {
                    Router.shared.openGallery(collectionID)
                } label: {
                    Label("Galerie", systemImage: "square.grid.2x2")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Picker("", selection: $nav.collectionTab) {
                ForEach(CollectionTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
            .padding(.bottom, 4)

            Group {
                switch nav.collectionTab {
                case .search: CollectionSearchTab(collection: binding)
                case .sources: CollectionSourcesTab(collection: binding)
                case .style: CollectionStyleTab(collection: binding, collectionID: collectionID)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: Reiter „Suche“

private struct CollectionSearchTab: View {
    @Binding var collection: PhotoCollection

    var body: some View {
        Form {
            Section("Allgemein") {
                TextField("Name", text: $collection.name)
            }
            Section {
                TokenEditor(title: "Schlagwörter",
                            tokens: $collection.keywords,
                            placeholder: "z. B. low key portrait, Enter zum Hinzufügen")
            } header: {
                Text("Wonach suchen?")
            } footer: {
                Text("Englische Begriffe liefern die meisten Treffer. Polux kombiniert sie zufällig und ergänzt gelernte Stilbegriffe aus deinen Likes.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section {
                Picker("Person im Bild", selection: $collection.subject) {
                    ForEach(SubjectFocus.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Wer soll zu sehen sein?")
            } footer: {
                Text("Polux ergänzt die Suche um den passenden Begriff (z. B. „woman“) und sortiert Fotos aus, die laut Titel und Tags eindeutig nicht passen. Fotos ohne Beschreibung können trotzdem durchrutschen.")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("Was ausschließen?") {
                TokenEditor(title: "Ausschlusswörter",
                            tokens: $collection.excludedWords,
                            placeholder: "z. B. wedding, selfie")
            }
            Section("Bildsprache") {
                Toggle("Aktfotografie & Mature-Inhalte zulassen", isOn: $collection.allowNudity)
                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: $collection.darkBias, in: 0...1) {
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
                Toggle("Nur Fotografien (keine Illustrationen)", isOn: $collection.photosOnly)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Reiter „Quellen“

private struct CollectionSourcesTab: View {
    @Binding var collection: PhotoCollection
    @ObservedObject private var tester = ConnectionTester.shared
    @State private var newFeed = ""

    var body: some View {
        Form {
            Section {
                ForEach(SourceKind.menuOrder.filter { $0 != .rss }) { kind in
                    sourceRow(kind)
                }
            } header: {
                Text("Bildquellen dieser Sammlung")
            } footer: {
                Text("Schlüssel gelten für alle Sammlungen und werden unter „Zugänge & Quellen“ verwaltet.")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section {
                Toggle(isOn: sourceBinding(.rss)) {
                    Label("Pinterest-Boards & RSS-Feeds verwenden", systemImage: SourceKind.rss.icon)
                }
                ForEach(collection.feeds, id: \.self) { feed in
                    HStack {
                        Text(feed).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        FeedTestButton(feed: feed)
                        Button {
                            collection.feeds.removeAll { $0 == feed }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .help("Board entfernen")
                    }
                }
                HStack {
                    TextField("Board-Adresse", text: $newFeed, prompt: Text("https://www.pinterest.com/nutzer/board/"))
                        .onSubmit(addFeed)
                    Button("Hinzufügen", action: addFeed)
                        .disabled(newFeed.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Pinterest-Boards")
            } footer: {
                HStack(spacing: 4) {
                    Text("Nur öffentliche Boards. Auch andere Bild-Feeds (Tumblr, Flickr-Gruppen) funktionieren.")
                    Button("Anleitung") { SettingsNavigation.shared.setUp(.rss) }
                        .buttonStyle(.link)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func sourceRow(_ kind: SourceKind) -> some View {
        HStack(spacing: 10) {
            Image(systemName: kind.icon).frame(width: 20).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title)
                Text(kind.tagline).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            StatusPill(kind: kind)
            if tester.status(kind) == .missing || isFailed(kind) {
                Button(tester.status(kind) == .missing ? "Einrichten …" : "Prüfen …") {
                    SettingsNavigation.shared.setUp(kind)
                }
            }
            Toggle("", isOn: sourceBinding(kind))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private func isFailed(_ kind: SourceKind) -> Bool {
        if case .failed = tester.status(kind) { return true }
        return false
    }

    private func sourceBinding(_ kind: SourceKind) -> Binding<Bool> {
        Binding(
            get: { collection.sources.contains(kind) },
            set: { on in
                if on { collection.sources.insert(kind) } else { collection.sources.remove(kind) }
            }
        )
    }

    private func addFeed() {
        let f = newFeed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty, RSSProvider.normalizedFeedURL(f) != nil else { return }
        if !collection.feeds.contains(f) { collection.feeds.append(f) }
        collection.sources.insert(.rss)
        newFeed = ""
    }
}

// MARK: Reiter „Stil & Fotos“

private struct CollectionStyleTab: View {
    @Binding var collection: PhotoCollection
    let collectionID: UUID
    @EnvironmentObject var store: LibraryStore
    @State private var confirmDelete = false

    var body: some View {
        let learned = StyleEngine.termProfile(for: collection).learned
        Form {
            Section {
                if learned.isEmpty {
                    Text("Noch nichts gelernt – like Fotos im Polaroid, dann erweitert Polux die Suche automatisch um passende Stilbegriffe.")
                        .foregroundColor(.secondary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(learned, id: \.self) { Chip(text: $0) }
                    }
                }
            } header: {
                Text("Gelernter Stil")
            } footer: {
                Text("Abgeleitet aus Motiv, Tags, Helligkeit und visueller Ähnlichkeit deiner Lieblingsfotos – komplett auf deinem Mac.")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("Lieblingsfotos") {
                LabeledContent("Anzahl", value: "\(collection.likes.count)")
                LabeledContent("Speicher", value: Paths.formatBytes(Int64(collection.totalBytes)))
                Button("Galerie öffnen") { Router.shared.openGallery(collectionID) }
            }

            Section {
                LabeledContent("Aus der Galerie entfernte Fotos", value: "\(collection.rejectedPrints.count)")
                Button("Negativ-Signale zurücksetzen") { store.resetRejections(collectionID) }
                    .disabled(collection.rejectedTags.isEmpty && collection.rejectedPrints.isEmpty)
            } header: {
                Text("Nicht gewünscht")
            } footer: {
                Text("Entfernte Fotos drücken ähnliche Vorschläge nach hinten.")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section {
                Button("Sammlung löschen …", role: .destructive) { confirmDelete = true }
                    .disabled(store.collections.count <= 1)
            } footer: {
                if store.collections.count <= 1 {
                    Text("Die letzte Sammlung kann nicht gelöscht werden.").font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .alert("Sammlung löschen?", isPresented: $confirmDelete) {
            Button("Löschen", role: .destructive) {
                store.deleteCollection(collectionID)
                SettingsNavigation.shared.openCollection(store.currentCollectionID, tab: .search)
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("„\(collection.name)“ und alle gelikten Fotos darin werden entfernt.")
        }
    }
}
