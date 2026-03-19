import AppKit
import SwiftUI

/// A floating, always-on-top, draggable widget window styled like an Apple desktop widget
class ScoreWidgetWindow: NSPanel {
    let eventId: String

    init(eventId: String, poller: ScorePoller, position: NSPoint, onClose: @escaping () -> Void) {
        self.eventId = eventId

        super.init(
            contentRect: NSRect(x: position.x, y: position.y, width: 280, height: 140),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.hasShadow = false // Widget view has its own shadow
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false

        let hostingView = NSHostingView(
            rootView: ScoreWidgetView(
                eventId: eventId,
                poller: poller,
                onClose: { [weak self] in
                    self?.close()
                    onClose()
                }
            )
        )
        self.contentView = hostingView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
