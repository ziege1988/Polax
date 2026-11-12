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

    /// Bildfläche: Ziehen verschiebt das Fenster, Doppelklick öffnet die Galerie.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, let content = contentView {
            let p = event.locationInWindow
            let flipped = CGPoint(x: p.x, y: content.bounds.height - p.y)
            if DragRegion.shared.rect.contains(flipped) {
                if event.clickCount >= 2 {
                    onDoubleClick?()
                } else {
                    performDrag(with: event)
                }
                return
            }
        }
        super.sendEvent(event)
    }
}

/// Reagiert auch auf den ersten Klick, wenn das Widget nicht aktiv ist.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
