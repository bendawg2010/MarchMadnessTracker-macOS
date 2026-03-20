import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var toolbarWindow: ToolbarWindow?
    private var widgetWindows: [String: ScoreWidgetWindow] = [:]
    private var settingsWindow: NSWindow?
    private var gameDetailWindows: [String: NSWindow] = [:]
    private var watchWindows: [String: NSWindow] = [:]
    private var multiviewWindow: NSWindow?
    let poller = ScorePoller()
    let notificationService = NotificationService()
    private var wasAutoHidden = false
    private var tickerSizeObserver: NSKeyValueObservation?

    var isToolbarVisible: Bool {
        toolbarWindow?.isVisible ?? false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        setupNotifications()
        setupViewNotifications()
        poller.startPolling()

        observeScoreUpdates()
        observeTickerSizeChanges()

        if UserDefaults.standard.bool(forKey: "toolbarEnabled") {
            showToolbar()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        poller.stopPolling()
        toolbarWindow?.close()
        widgetWindows.values.forEach { $0.close() }
        settingsWindow?.close()
        gameDetailWindows.values.forEach { $0.close() }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "basketball.fill", accessibilityDescription: "March Madness")
            button.image?.size = NSSize(width: 18, height: 18)
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: Constants.popoverWidth, height: Constants.popoverHeight)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: PopoverContentView(
                poller: poller,
                onToggleToolbar: { [weak self] in self?.toggleToolbar() },
                onOpenSettings: { [weak self] in self?.openSettings() }
            )
        )
    }

    // MARK: - Toolbar Window

    func showToolbar() {
        if toolbarWindow == nil {
            toolbarWindow = ToolbarWindow(poller: poller, onClose: { [weak self] in
                self?.hideToolbar()
            }, onDetachGame: { [weak self] event in
                self?.createWidget(for: event)
            })
        }
        toolbarWindow?.orderFront(nil)
        UserDefaults.standard.set(true, forKey: "toolbarEnabled")
        wasAutoHidden = false
    }

    func hideToolbar() {
        toolbarWindow?.orderOut(nil)
        UserDefaults.standard.set(false, forKey: "toolbarEnabled")
    }

    func toggleToolbar() {
        if isToolbarVisible {
            hideToolbar()
        } else {
            showToolbar()
        }
        popover.contentViewController = NSHostingController(
            rootView: PopoverContentView(
                poller: poller,
                onToggleToolbar: { [weak self] in self?.toggleToolbar() },
                onOpenSettings: { [weak self] in self?.openSettings() }
            )
        )
    }

    // MARK: - Score Widgets

    func createWidget(for event: Event) {
        guard widgetWindows[event.id] == nil else {
            // Already exists, bring to front
            widgetWindows[event.id]?.orderFront(nil)
            return
        }

        // Position: cascade from top-right of screen
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let widgetCount = CGFloat(widgetWindows.count)
        let x = screen.frame.width - 300 - (widgetCount * 20)
        let y = screen.frame.height - 200 - (widgetCount * 30)

        let widget = ScoreWidgetWindow(
            eventId: event.id,
            poller: poller,
            position: NSPoint(x: x, y: y),
            onClose: { [weak self] in
                self?.widgetWindows.removeValue(forKey: event.id)
            }
        )
        widget.orderFront(nil)
        widgetWindows[event.id] = widget
    }

    // MARK: - Settings Window

    func openSettings() {
        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "March Madness Settings"
        window.contentViewController = NSHostingController(rootView: SettingsView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    // MARK: - Game Detail Window

    func openGameDetail(for event: Event) {
        // If already open, bring to front
        if let existing = gameDetailWindows[event.id], existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 280),
            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.title = "\(event.awayCompetitor?.team.abbreviation ?? "Away") vs \(event.homeCompetitor?.team.abbreviation ?? "Home")"
        window.isFloatingPanel = true
        window.level = .floating
        window.contentViewController = NSHostingController(
            rootView: GameDetailView(event: event, onCreateWidget: { [weak self] in
                self?.createWidget(for: event)
            })
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        gameDetailWindows[event.id] = window
    }

    // MARK: - View Notifications

    private func setupViewNotifications() {
        NotificationCenter.default.addObserver(
            forName: .openGameDetail,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let eventId = notification.userInfo?["eventId"] as? String,
                  let event = self?.poller.games.first(where: { $0.id == eventId }) else { return }
            self?.openGameDetail(for: event)
        }

        NotificationCenter.default.addObserver(
            forName: .createGameWidget,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let eventId = notification.userInfo?["eventId"] as? String,
                  let event = self?.poller.games.first(where: { $0.id == eventId }) else { return }
            self?.createWidget(for: event)
        }

        // Watch notifications
        NotificationCenter.default.addObserver(
            forName: .openWatchPortal,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.openWatchPortal()
        }

        NotificationCenter.default.addObserver(
            forName: .openWatchGame,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let eventId = notification.userInfo?["eventId"] as? String,
                  let event = self?.poller.games.first(where: { $0.id == eventId }) else { return }
            self?.openWatchGame(event)
        }

        NotificationCenter.default.addObserver(
            forName: .openMultiview,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.openMultiview()
        }
    }

    // MARK: - Watch

    private func openWatchPortal() {
        let url = URL(string: "https://www.ncaa.com/march-madness-live/watch")!
        let window = WatchGameWindow(url: url, title: "🏀 March Madness Live")
        watchWindows["portal"] = window
    }

    private func openWatchGame(_ event: Event) {
        if let existing = watchWindows[event.id], existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Try ESPN watch page for the specific game
        let url = URL(string: "https://www.espn.com/mens-college-basketball/game/_/gameId/\(event.id)")!
        let away = event.awayCompetitor?.team.abbreviation ?? "Away"
        let home = event.homeCompetitor?.team.abbreviation ?? "Home"
        let window = WatchGameWindow(url: url, title: "📺 \(away) vs \(home)")
        watchWindows[event.id] = window
    }

    private func openMultiview() {
        if let existing = multiviewWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let liveGames = poller.games.filter { $0.isLive }
        if liveGames.isEmpty { return }

        // Rank games by excitement: close score, upsets, later rounds
        let ranked = liveGames.sorted { a, b in
            gameExcitementScore(a) > gameExcitementScore(b)
        }
        let gamesToShow = Array(ranked.prefix(4))

        let streams: [(url: URL, title: String)] = gamesToShow.compactMap { game in
            let away = game.awayCompetitor?.team.abbreviation ?? "Away"
            let home = game.homeCompetitor?.team.abbreviation ?? "Home"
            // Use ESPN game page for actual game content
            let url = URL(string: "https://www.espn.com/mens-college-basketball/game/_/gameId/\(game.id)")!
            return (url: url, title: "\(away) vs \(home)")
        }

        let window = MultiviewWindow(urls: streams)
        multiviewWindow = window
    }

    /// Score how exciting a game is — higher = better game to watch
    private func gameExcitementScore(_ game: Event) -> Int {
        var score = 0

        // Close games are more exciting (lower point diff = higher score)
        if let diff = game.scoreDifference {
            score += max(0, 20 - diff) * 3 // 0-pt game = 60, 5-pt game = 45, 20+ = 0
        }

        // Upsets are exciting (lower seed winning)
        if let awaySeed = game.awayCompetitor?.seed,
           let homeSeed = game.homeCompetitor?.seed,
           let awayScore = game.awayCompetitor?.scoreInt,
           let homeScore = game.homeCompetitor?.scoreInt {
            let seedDiff = abs(awaySeed - homeSeed)
            if (awaySeed > homeSeed && awayScore > homeScore) ||
               (homeSeed > awaySeed && homeScore > awayScore) {
                score += seedDiff * 4 // Big upset = big bonus
            }
        }

        // Later rounds are more important
        let round = game.roundName ?? ""
        switch round {
        case _ where round.contains("Championship"): score += 50
        case _ where round.contains("Final Four"):    score += 40
        case _ where round.contains("Elite"):         score += 30
        case _ where round.contains("Sweet"):         score += 20
        case _ where round.contains("2nd"):           score += 10
        default:                                       score += 5
        }

        // Later in the game = more exciting (2nd half, OT)
        if game.status.period >= 3 { // OT
            score += 25
        } else if game.status.period == 2 { // 2nd half
            score += 10
        }

        return score
    }

    // MARK: - Ticker Size

    private func observeTickerSizeChanges() {
        // Watch for ticker size preference changes
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateToolbarSize()
        }
    }

    private func updateToolbarSize() {
        guard let toolbarWindow else { return }
        let size = UserDefaults.standard.double(forKey: "tickerSize")
        let height = size > 0 ? size : 38

        if let screen = NSScreen.main {
            let menuBarHeight = screen.frame.height - screen.visibleFrame.height - screen.visibleFrame.origin.y
            let yPos = screen.frame.height - menuBarHeight - height
            toolbarWindow.setFrame(
                NSRect(x: 0, y: yPos, width: screen.frame.width, height: height),
                display: true,
                animate: true
            )
        }
    }

    // MARK: - Auto-hide ticker when no games

    private func updateToolbarAutoHide() {
        let toolbarEnabled = UserDefaults.standard.bool(forKey: "toolbarEnabled")
        let hasActiveGames = !poller.tickerGames.isEmpty

        if toolbarEnabled || wasAutoHidden {
            if hasActiveGames && !isToolbarVisible {
                if toolbarWindow == nil {
                    toolbarWindow = ToolbarWindow(poller: poller, onClose: { [weak self] in
                        self?.hideToolbar()
                    }, onDetachGame: { [weak self] event in
                        self?.createWidget(for: event)
                    })
                }
                toolbarWindow?.orderFront(nil)
                wasAutoHidden = false
            } else if !hasActiveGames && isToolbarVisible {
                toolbarWindow?.orderOut(nil)
                wasAutoHidden = true
            }
        }
    }

    // MARK: - Notifications

    private func setupNotifications() {
        notificationService.requestPermission()

        if UserDefaults.standard.object(forKey: "notificationsEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "notificationsEnabled")
        }
        if UserDefaults.standard.integer(forKey: "closeGameThreshold") == 0 {
            UserDefaults.standard.set(Constants.closeGamePointThreshold, forKey: "closeGameThreshold")
        }
    }

    // MARK: - Updates

    private func observeScoreUpdates() {
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.updateMenuBarTitle()
            self.notificationService.checkForCloseGames(events: self.poller.games)
            self.notificationService.checkForUpsets(events: self.poller.games)
            self.updateToolbarAutoHide()
        }
    }

    private func updateMenuBarTitle() {
        guard let favoriteTeamId = UserDefaults.standard.string(forKey: "favoriteTeamId"),
              !favoriteTeamId.isEmpty,
              let game = poller.gameForTeam(teamId: favoriteTeamId),
              let button = statusItem.button else {
            statusItem.button?.title = ""
            return
        }

        if game.isLive {
            let away = game.awayCompetitor
            let home = game.homeCompetitor
            button.title = " \(away?.team.abbreviation ?? "") \(away?.score ?? "0")-\(home?.score ?? "0") \(home?.team.abbreviation ?? "")"
        } else if game.isScheduled {
            if let date = game.startDate {
                button.title = " \(DateFormatters.timeOnly.string(from: date))"
            } else {
                button.title = ""
            }
        } else {
            button.title = ""
        }
    }

    // MARK: - Actions

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
