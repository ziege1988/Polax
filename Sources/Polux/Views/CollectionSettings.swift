import SwiftUI
import AppKit

// MARK: - Sammlung bearbeiten

struct CollectionEditor: View {
    let collectionID: UUID
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var engine: InspirationEngine
    @State private var newFeed = ""
    @State private var confirmDelete = false

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
                PageHeader(icon: "rectangle.stack", title: c.wrappedValue.name.isEmpty ? "Sammlung" : c.wrappedValue.name,
                           subtitle: "\(c.wrappedValue.likes.count) Lieblingsfotos · \(Paths.formatBytes(Int64(c.wrappedValue.totalBytes)))")
            }

            Section("Allgemein") {
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
                            SourceStatusBadge(kind: kind)
                            if kind.needsCredentials && !Providers.hasCredentials(kind) {
                                Button("Schlüssel fehlt") { SettingsNavigation.shared.page = .source(kind) }
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
                        FeedTestButton(feed: feed)
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
                SettingsNavigation.shared.page = .collection(store.currentCollectionID)
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("„\(c.wrappedValue.name)“ und alle gelikten Fotos darin werden entfernt.")
        }
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

