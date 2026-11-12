import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let settings = AppSettings.shared
    private(set) lazy var store = LibraryStore()
    private(set) lazy var engine = InspirationEngine(store: store, settings: settings)
    let updater = UpdateChecker.shared

    private var polaroidWindow: PolaroidWindow?
    private var galleryWindows: [UUID: NSWindow] = [:]
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var pauseItem: NSMenuItem?
    private var updateItem: NSMenuItem?
    private var bag = Set<AnyCancellable>()

    private let positionKey = "polaroidTopLeft"

    // MARK: Lebenszyklus

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-preview"), i + 1 < args.count {
            PreviewRenderer.render(to: URL(fileURLWithPath: args[i + 1]), store: store, engine: engine,
                                   settings: settings, updater: updater)
            NSApp.terminate(nil)
            return
        }

        Router.shared.openGallery = { [weak self] id in self?.showGallery(id) }
        Router.shared.openSettings = { [weak self] tab in self?.showSettings(tab) }
        Router.shared.resetPosition = { [weak self] in self?.resetPosition() }

        LaunchAtLogin.enableOnFirstRun()
        setupStatusItem()
        setupPolaroidWindow()
        engine.start()

        settings.$windowLevel
            .sink { [weak self] level in self?.polaroidWindow?.apply(level: level) }
            .store(in: &bag)
        settings.$polaroidSize.dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.fitWindowToContent() } }
            .store(in: &bag)
        updater.$state
            .sink { [weak self] state in
                guard let item = self?.updateItem else { return }
                if case .available(let v, _) = state {
                    item.title = "Update auf \(v) verfügbar …"
                } else {
                    item.title = "Nach Updates suchen …"
                }
            }
            .store(in: &bag)

        Task { await updater.checkIfDue() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPolaroid()
        return true
    }

    // MARK: Polaroid-Fenster

    private func setupPolaroidWindow() {
        let root = PolaroidView()
            .environmentObject(store)
            .environmentObject(engine)
            .environmentObject(settings)
            .environmentObject(updater)
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.sizingOptions = [.intrinsicContentSize]
        let size = hosting.fittingSize
        let window = PolaroidWindow(contentRect: NSRect(origin: .zero, size: size))
        window.contentView = hosting
        window.delegate = self
        window.apply(level: settings.windowLevel)
        window.setFrameOrigin(restoredOrigin(for: size))
        window.onDoubleClick = { [weak self] in
            guard let self else { return }
            self.showGallery(self.store.currentCollectionID)
        }
        window.orderFrontRegardless()
        polaroidWindow = window
    }

    private func fitWindowToContent() {
        guard let w = polaroidWindow, let content = w.contentView else { return }
        let size = content.fittingSize
        let top = w.frame.maxY
        w.setFrame(NSRect(x: w.frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    private func restoredOrigin(for size: NSSize) -> NSPoint {
        if let s = UserDefaults.standard.string(forKey: positionKey) {
            let topLeft = NSPointFromString(s)
            let frame = NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
            let visible = NSScreen.screens.contains { $0.visibleFrame.insetBy(dx: -40, dy: -40).intersects(frame.insetBy(dx: 60, dy: 60)) }
            if visible { return frame.origin }
        }
        let vf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: vf.maxX - size.width - 10, y: vf.maxY - size.height - 10)
    }

    private func resetPosition() {
        UserDefaults.standard.removeObject(forKey: positionKey)
        guard let w = polaroidWindow else { return }
        w.setFrameOrigin(restoredOrigin(for: w.frame.size))
    }

    func windowDidMove(_ notification: Notification) {
        guard let w = notification.object as? NSWindow, w === polaroidWindow else { return }
        let topLeft = NSPoint(x: w.frame.minX, y: w.frame.maxY)
        UserDefaults.standard.set(NSStringFromPoint(topLeft), forKey: positionKey)
    }

    private func showPolaroid() {
        polaroidWindow?.orderFrontRegardless()
    }

    // MARK: Galerie & Einstellungen

    func showGallery(_ collectionID: UUID) {
        if let w = galleryWindows[collectionID] {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        let view = GalleryView(collectionID: collectionID)
            .environmentObject(store)
            .environmentObject(engine)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "Polux – \(store.collection(collectionID)?.name ?? "Galerie")"
        w.contentView = NSHostingView(rootView: view)
        w.isReleasedWhenClosed = false
        w.setFrameAutosaveName("PoluxGallery")
        if w.frame.origin == .zero { w.center() }
        w.delegate = self
        galleryWindows[collectionID] = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func showSettings(_ tab: SettingsTab) {
        SettingsNavigation.shared.tab = tab
        if settingsWindow == nil {
            let view = SettingsView()
                .environmentObject(store)
                .environmentObject(engine)
                .environmentObject(settings)
                .environmentObject(updater)
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Polux – Einstellungen"
            w.contentView = NSHostingView(rootView: view)
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        if let key = galleryWindows.first(where: { $0.value === w })?.key {
            galleryWindows[key] = nil
        }
    }

    // MARK: Menüleiste

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let img = NSImage(systemSymbolName: "camera.aperture", accessibilityDescription: "Polux")
            img?.isTemplate = true
            button.image = img
            button.toolTip = "Polux"
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Polaroid anzeigen", action: #selector(menuShowPolaroid), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Nächstes Foto", action: #selector(menuNext), keyEquivalent: "").target = self
        let pause = menu.addItem(withTitle: "Pause", action: #selector(menuTogglePause), keyEquivalent: "")
        pause.target = self
        pauseItem = pause
        menu.addItem(withTitle: "Galerie öffnen", action: #selector(menuGallery), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Einstellungen …", action: #selector(menuSettings), keyEquivalent: ",").target = self
        let upd = menu.addItem(withTitle: "Nach Updates suchen …", action: #selector(menuUpdates), keyEquivalent: "")
        upd.target = self
        updateItem = upd
        menu.addItem(.separator())
        menu.addItem(withTitle: "Polux beenden", action: #selector(menuQuit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        pauseItem?.title = settings.isPaused ? "Fortsetzen" : "Pause"
    }

    @objc private func menuShowPolaroid() { showPolaroid() }
    @objc private func menuNext() { engine.next() }
    @objc private func menuTogglePause() { engine.togglePause() }
    @objc private func menuGallery() { showGallery(store.currentCollectionID) }
    @objc private func menuSettings() { showSettings(.collections) }
    @objc private func menuUpdates() {
        showSettings(.updates)
        if updater.availableVersion == nil { Task { await updater.check() } }
    }
    @objc private func menuQuit() { NSApp.terminate(nil) }
}
