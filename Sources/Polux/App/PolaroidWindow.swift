import AppKit
import SwiftUI

/// Rahmenloses, frei verschiebbares Fenster für das Polaroid-Widget.
final class PolaroidWindow: NSWindow {
    var onDoubleClick: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false   // Schatten zeichnet SwiftUI
        isMovable = true
        isReleasedWhenClosed = false
        title = "Polux"
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func apply(level: WidgetLevel) {
        switch level {
        case .desktop:
            self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        case .normal:
            self.level = .normal
            collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        case .floating:
            self.level = .floating
            collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        }
    }

    /// Ziehen an jeder Stelle des Polaroids (Rahmen, Ecken, Foto, Beschriftung) verschiebt das Fenster.
    /// Ein Klick ohne Bewegung wird normal an Knöpfe und Menüs weitergegeben.
    /// Doppelklick auf das Foto öffnet die Galerie.
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .leftMouseDown, let content = contentView else {
            super.sendEvent(event)
            return
        }
        let p = event.locationInWindow
        let flipped = CGPoint(x: p.x, y: content.bounds.height - p.y)

        if event.clickCount >= 2, DragRegion.shared.rect.contains(flipped) {
            onDoubleClick?()
            return
        }

        // Klick oder Ziehen? Erst nach 3 pt Bewegung wird verschoben.
        let startMouse = NSEvent.mouseLocation
        let startOrigin = frame.origin
        var dragging = false
        var mouseUp: NSEvent?

        while let next = nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                   until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if next.type == .leftMouseUp {
                mouseUp = next
                break
            }
            let now = NSEvent.mouseLocation
            let dx = now.x - startMouse.x, dy = now.y - startMouse.y
            if !dragging && (dx * dx + dy * dy) > 9 { dragging = true }
            if dragging {
                setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
            }
        }

        guard !dragging else { return }
        // Normaler Klick: Loslassen zurück in die Warteschlange, dann Klick weitergeben.
        if let up = mouseUp { postEvent(up, atStart: true) }
        super.sendEvent(event)
    }
}

/// Reagiert auch auf den ersten Klick, wenn das Widget nicht aktiv ist.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
