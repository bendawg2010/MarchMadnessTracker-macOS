import AppKit
import SwiftUI

/// A borderless, always-on-top floating toolbar window that shows a scrolling sports ticker
class ToolbarWindow: NSPanel {
    var onClose: (() -> Void)?

    init(poller: ScorePoller, onClose: @escaping () -> Void, onDetachGame: ((Event) -> Void)? = nil) {
        let screenWidth = NSScreen.main?.frame.width ?? 1440
        let tickerSize = UserDefaults.standard.double(forKey: "tickerSize")
        let toolbarHeight: CGFloat = tickerSize > 0 ? tickerSize : Constants.toolbarHeight

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: screenWidth, height: toolbarHeight),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        self.onClose = onClose

        self.level = .statusBar
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false

        if let screen = NSScreen.main {
            let menuBarHeight = screen.frame.height - screen.visibleFrame.height - screen.visibleFrame.origin.y
            let yPos = screen.frame.height - menuBarHeight - toolbarHeight
            self.setFrameOrigin(NSPoint(x: 0, y: yPos))
            self.setContentSize(NSSize(width: screen.frame.width, height: toolbarHeight))
        }

        let hostingView = NSHostingView(
            rootView: ToolbarTickerView(poller: poller, onClose: { [weak self] in
                self?.onClose?()
            }, onDetachGame: { event in
                onDetachGame?(event)
            })
        )
        self.contentView = hostingView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
