import SwiftUI
import AppKit

/// Merkt sich die Bildfläche, damit das Fenster dort verschoben bzw. per Doppelklick
/// die Galerie geöffnet werden kann.
final class DragRegion {
    static let shared = DragRegion()
    var rect: CGRect = .zero
}

private struct PhotoFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct PolaroidView: View {
    @EnvironmentObject var engine: InspirationEngine
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var updater: UpdateChecker

    @State private var showDrawer = false
    @State private var heartPulse = false

    /// Außenabstand für den Schatten.
    static let shadowMargin: CGFloat = 26

    var body: some View {
        let w = settings.polaroidSize.width
        let pad = (w * 0.045).rounded()
        let imageW = w - pad * 2
        let imageH = (imageW * 1.25).rounded()

        VStack(alignment: .leading, spacing: 0) {
            photo(width: imageW, height: imageH)
            caption(width: w)
                .padding(.horizontal, pad * 0.35)
                .padding(.top, pad * 1.05)
                .padding(.bottom, pad * 0.95)
        }
        .padding([.top, .horizontal], pad)
        .frame(width: w)
        .background(
            RoundedRectangle(cornerRadius: w * 0.028, style: .continuous)
                .fill(Theme.cream)
        )
        .overlay(
            RoundedRectangle(cornerRadius: w * 0.028, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        )
        .overlay(alignment: .topTrailing) {
            CloseButton(size: max(8, pad * 0.62))
                .padding(.top, (pad - max(8, pad * 0.62) * 1.6) / 2)
                .padding(.trailing, (pad - max(8, pad * 0.62) * 1.6) / 2)
        }
        .shadow(color: .black.opacity(0.32), radius: 16, x: 0, y: 9)
        .padding(Self.shadowMargin)
        .environment(\.colorScheme, .light)
    }

    // MARK: Bild

    @ViewBuilder
    private func photo(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Theme.photoBackground
            if let img = engine.currentImage {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
                    .id(engine.current?.id)
                    .transition(.opacity)
            } else {
                VStack(spacing: 14) {
                    PoluxWordmark(size: 22, inverted: false)
                        .colorInvert()
                        .opacity(0.7)
                    if engine.isBusy {
                        ProgressView().controlSize(.small).colorScheme(.dark)
                    } else {
                        Text(engine.statusMessage ?? "Warte auf das erste Foto …")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 6) {
                if engine.isBusy && engine.currentImage != nil {
                    ProgressView().controlSize(.mini).colorScheme(.dark)
                }
                if settings.isPaused {
                    Text("PAUSE")
                        .font(.system(size: 9, weight: .bold))
                        .kerning(1)
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                }
            }
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .background(
            GeometryReader { g in
                Color.clear.preference(key: PhotoFrameKey.self, value: g.frame(in: .global))
            }
        )
        .onPreferenceChange(PhotoFrameKey.self) { DragRegion.shared.rect = $0 }
        .help("Ziehen zum Verschieben · Doppelklick öffnet die Galerie")
        .accessibilityLabel(engine.current?.candidate.title ?? "Inspirationsfoto")
    }

    // MARK: Rahmen unten

    @ViewBuilder
    private func caption(width w: CGFloat) -> some View {
        let icon = (w * 0.058).rounded()
        VStack(alignment: .leading, spacing: w * 0.03) {
            HStack(alignment: .center, spacing: w * 0.02) {
                Button { showDrawer.toggle() } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: icon * 0.9, weight: .medium))
                        .foregroundColor(Theme.ink)
                        .frame(width: icon * 1.3, height: icon * 1.3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Sammlungen")
                .popover(isPresented: $showDrawer, arrowEdge: .bottom) {
                    CollectionDrawer(close: { showDrawer = false })
                        .environmentObject(store)
                        .environmentObject(engine)
                }

                Text(store.currentCollection.name)
                    .font(.system(size: w * 0.07, weight: .semibold))
                    .foregroundColor(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .onTapGesture { showDrawer.toggle() }

                Spacer(minLength: 4)

                Text(engine.counterText)
                    .font(.system(size: w * 0.046))
                    .monospacedDigit()
                    .foregroundColor(Theme.muted)

                ZStack(alignment: .topTrailing) {
                    PolaroidIconButton(systemName: "gearshape", size: icon * 0.85, color: Theme.muted,
                                       help: "Einstellungen") {
                        Router.shared.openSettings(updater.availableVersion != nil ? .updates : .collections)
                    }
                    if updater.availableVersion != nil {
                        Circle().fill(Color.orange).frame(width: 7, height: 7).offset(x: -2, y: 2)
                    }
                }
            }

            HStack(spacing: w * 0.025) {
                PolaroidIconButton(systemName: engine.isCurrentLiked ? "heart.fill" : "heart",
                                   size: icon,
                                   color: engine.isCurrentLiked ? Theme.heart : Theme.ink,
                                   help: engine.isCurrentLiked ? "Like entfernen" : "Gefällt mir – Stil merken") {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) { heartPulse = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { heartPulse = false }
                    engine.toggleLike()
                }
                .scaleEffect(heartPulse ? 1.25 : 1)
                .disabled(engine.current == nil)

                addToCollectionMenu(icon: icon)

                PolaroidIconButton(systemName: "arrow.up.forward.square", size: icon * 0.95,
                                   help: "Originalquelle öffnen") {
                    if let c = engine.current?.candidate {
                        NSWorkspace.shared.open(c.pageURL ?? c.imageURL)
                    }
                }
                .disabled(engine.current == nil)

                Spacer()

                PolaroidIconButton(systemName: "chevron.left", size: icon * 0.9, help: "Vorheriges Foto") {
                    engine.previous()
                }
                .disabled(engine.index <= 0)
                .opacity(engine.index <= 0 ? 0.35 : 1)

                PolaroidIconButton(systemName: settings.isPaused ? "play.circle" : "pause.circle",
                                   size: icon, help: settings.isPaused ? "Fortsetzen" : "Pause") {
                    engine.togglePause()
                }

                PolaroidIconButton(systemName: "chevron.right", size: icon * 0.9, help: "Nächstes Foto") {
                    engine.next()
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(engine.tagLine)
                    .font(.system(size: w * 0.038))
                    .kerning(0.6)
                    .foregroundColor(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                PoluxWordmark(size: w * 0.047)
            }
        }
    }

    @ViewBuilder
    private func addToCollectionMenu(icon: CGFloat) -> some View {
        if PreviewRenderer.isRendering {
            // Menüs lassen sich offscreen nicht rendern – in der Vorschau nur das Symbol zeigen.
            Image(systemName: "folder.badge.plus")
                .font(.system(size: icon * 0.95))
                .foregroundColor(Theme.ink)
                .frame(width: icon * 1.5, height: icon * 1.5)
        } else {
            collectionMenu(icon: icon)
        }
    }

    private func collectionMenu(icon: CGFloat) -> some View {
        let others = store.collections.filter { $0.id != store.currentCollectionID }
        return Menu {
            if others.isEmpty {
                Text("Keine weiteren Sammlungen")
            } else {
                Section("Zu Sammlung hinzufügen") {
                    ForEach(others) { c in
                        Button {
                            engine.addCurrent(to: c.id)
                        } label: {
                            if let id = engine.current?.candidate.id, store.isLiked(id, in: c.id) {
                                Label(c.name, systemImage: "checkmark")
                            } else {
                                Text(c.name)
                            }
                        }
                    }
                }
            }
            Divider()
            Button("Neue Sammlung …") { Router.shared.openSettings(.collections) }
        } label: {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: icon * 0.95))
                .foregroundColor(Theme.ink)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: icon * 1.5, height: icon * 1.5)
        .help("Zu einer anderen Sammlung hinzufügen")
        .disabled(engine.current == nil)
    }
}

/// Dezentes x oben rechts im Rahmen – beendet Polux.
private struct CloseButton: View {
    var size: CGFloat
    @State private var hovering = false

    var body: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(Theme.muted.opacity(hovering ? 1 : 0.55))
                .frame(width: size * 1.6, height: size * 1.6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Polux beenden")
    }
}

// MARK: - Sammlungs-Reiter (Burger-Menü)

struct CollectionDrawer: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var engine: InspirationEngine
    var close: () -> Void

    @State private var selection: UUID?
    @State private var newName = ""
    @State private var pendingDelete: PhotoCollection?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SAMMLUNGEN")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.2)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    close()
                    Router.shared.openSettings(.collections)
                } label: {
                    Image(systemName: "gearshape").font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .help("Sammlungen verwalten")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            List(selection: $selection) {
                ForEach(store.collections) { c in
                    HStack(spacing: 8) {
                        Image(systemName: c.id == store.currentCollectionID ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(c.id == store.currentCollectionID ? .accentColor : .secondary)
                        Text(c.name).lineLimit(1)
                        Spacer()
                        Text("\(c.likes.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Image(systemName: "line.3.horizontal")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.6))
                            .help("Zum Sortieren ziehen")
                    }
                    .padding(.vertical, 2)
                    .contextMenu {
                        Button("Galerie öffnen") {
                            close()
                            Router.shared.openGallery(c.id)
                        }
                        Button("Bearbeiten …") {
                            close()
                            Router.shared.openSettings(.collections)
                        }
                        Divider()
                        Button("Löschen …", role: .destructive) { pendingDelete = c }
                            .disabled(store.collections.count <= 1)
                    }
                }
                .onMove { store.moveCollections(from: $0, to: $1) }
            }
            .listStyle(.inset)
            .frame(height: min(CGFloat(store.collections.count), 8) * 30 + 14)

            Divider()

            HStack(spacing: 8) {
                TextField("Neue Sammlung …", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button(action: add) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Sammlung hinzufügen")
            }
            .padding(12)
        }
        .frame(width: 280)
        .onAppear { selection = store.currentCollectionID }
        .onChange(of: selection) { id in
            if let id, id != store.currentCollectionID { engine.switchCollection(to: id) }
        }
        .alert("Sammlung löschen?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { c in
            Button("Löschen", role: .destructive) {
                store.deleteCollection(c.id)
                selection = store.currentCollectionID
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { c in
            Text("„\(c.name)“ und \(c.likes.count) gelikte Fotos werden entfernt.")
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let id = store.addCollection(name: name)
        newName = ""
        selection = id
    }
}
