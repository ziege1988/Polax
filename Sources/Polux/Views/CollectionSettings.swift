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
                Toggle("Nur Bilder mit Personen", isOn: $collection.requirePeople)
                Label("Erlaubt sind Fotos und fotorealistische KI-Bilder mit Personen. Gemälde, gemalte Digitalkunst, Illustration, Anime/Comic, Stillleben und Abstraktes werden aussortiert.",
                      systemImage: "person.crop.rectangle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Reiter „Quellen“

private struct CollectionSourcesTab: View {
    @Binding var collection: PhotoCollection
    @ObservedObject private var tester = ConnectionTester.shared
    @ObservedObject private var nav = SettingsNavigation.shared

    var body: some View {
        let highlight = nav.highlightFeeds
        Form {
            if highlight { pinterestSection(highlight: true) }

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

            if !highlight { pinterestSection(highlight: false) }
        }
        .formStyle(.grouped)
        .onAppear {
            if highlight {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { nav.highlightFeeds = false }
            }
        }
    }

    private func pinterestSection(highlight: Bool) -> some View {
        Section {
            Toggle(isOn: Binding(
                get: { collection.sources.contains(.rss) },
                set: { on in
                    if on { collection.sources.insert(.rss) } else { collection.sources.remove(.rss) }
                    // Eingeschaltet, aber noch kein Board? Eingabefeld zeigen und hervorheben.
                    if on && collection.feeds.isEmpty { nav.highlightFeeds = true }
                }
            )) {
                Label("Pinterest-Boards & RSS-Feeds verwenden", systemImage: SourceKind.rss.icon)
            }
            FeedListEditor(collectionID: collection.id, highlight: highlight)
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

/// Liste der Pinterest-Boards/Feeds einer Sammlung mit Eingabefeld, Test und optionalem Aufleuchten.
struct FeedListEditor: View {
    let collectionID: UUID
    var highlight: Bool = false

    @EnvironmentObject var store: LibraryStore
    @State private var input = ""
    @State private var error: String?
    @State private var glow = false
    @FocusState private var focused: Bool

    var body: some View {
        let feeds = store.collection(collectionID)?.feeds ?? []
        VStack(alignment: .leading, spacing: 8) {
            ForEach(feeds, id: \.self) { feed in
                HStack(spacing: 8) {
                    Image(systemName: "pin.fill").foregroundColor(.secondary).font(.caption)
                    Text(feed).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    FeedTestButton(feed: feed)
                    Button {
                        store.mutate(collectionID) { c in c.feeds.removeAll { $0 == feed } }
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .help("Board entfernen")
                }
            }
            HStack(spacing: 8) {
                TextField("Board-Adresse", text: $input,
                          prompt: Text("Board-Adresse einfügen, z. B. pinterest.com/nutzer/boardname"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .focused($focused)
                    .onSubmit(add)
                Button("Hinzufügen", action: add)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let error {
                Text(error).font(.caption).foregroundColor(.red)
            }
        }
        .padding(6)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange, lineWidth: 2.5)
                .opacity(glow ? 1 : 0)
        )
        .onAppear {
            guard highlight else { return }
            focused = true
            withAnimation(.easeInOut(duration: 0.45).repeatCount(6, autoreverses: true)) { glow = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                withAnimation(.easeOut(duration: 0.4)) { glow = false }
            }
        }
    }

    private func add() {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let isShortLink = raw.lowercased().contains("pin.it/")
        let isPin = raw.lowercased().contains("/pin/")
        guard isShortLink || isPin || RSSProvider.normalizedFeedURL(raw) != nil else {
            error = "Diese Adresse wird nicht erkannt. Format: pinterest.com/nutzer/boardname"
            return
        }
        store.mutate(collectionID) { c in
            if !c.feeds.contains(raw) { c.feeds.append(raw) }
            c.sources.insert(.rss)
        }
        input = ""
        error = nil
    }
}
