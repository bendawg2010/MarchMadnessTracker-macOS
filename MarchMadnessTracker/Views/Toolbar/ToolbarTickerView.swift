import SwiftUI

struct ToolbarTickerView: View {
    var poller: ScorePoller
    var onClose: (() -> Void)?
    var onDetachGame: ((Event) -> Void)?
    @State private var scrollOffset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var scrollTimer: Timer?
    @State private var refreshTimer: Timer?
    @State private var isHovering = false
    @State private var now = Date()
    @AppStorage("tickerSize") private var tickerSize: Double = 38

    private var tickerGames: [Event] {
        poller.tickerGames
    }

    private var cardMode: CardMode {
        let count = tickerGames.count
        if count <= 2 { return .expanded }
        if count <= 5 { return .medium }
        return .compact
    }

    private var needsScroll: Bool {
        contentWidth > containerWidth && containerWidth > 0
    }

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)

            HStack(spacing: 0) {
                tickerArea
                    .frame(maxWidth: .infinity)

                // Right-side controls
                HStack(spacing: 6) {
                    if poller.hasLiveGames {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(.red)
                                .frame(width: 6, height: 6)
                                .overlay(
                                    Circle()
                                        .stroke(.red.opacity(0.5), lineWidth: 2)
                                        .frame(width: 10, height: 10)
                                )
                            Text("\(poller.liveGames.count) LIVE")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(.red)
                        }
                    }

                    Button {
                        onClose?()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovering ? 1 : 0.3)
                }
                .padding(.trailing, 8)
                .padding(.leading, 4)
            }
        }
        .frame(height: tickerSize)
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .onAppear {
            startClockRefresh()
        }
        .onDisappear {
            refreshTimer?.invalidate()
        }
    }

    // MARK: - Ticker Area

    @ViewBuilder
    private var tickerArea: some View {
        if tickerGames.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "basketball.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                Text("March Madness")
                    .font(.system(size: 12, weight: .semibold))
                if poller.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                } else {
                    Text("Waiting for games...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            GeometryReader { geo in
                let content = tickerContent
                Group {
                    if needsScroll {
                        HStack(spacing: 0) {
                            content
                                .background(GeometryReader { inner in
                                    Color.clear
                                        .onAppear { contentWidth = inner.size.width }
                                        .onChange(of: poller.lastUpdated) { _, _ in
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                contentWidth = inner.size.width
                                            }
                                        }
                                })
                            content
                        }
                        .offset(x: -scrollOffset)
                    } else {
                        HStack {
                            Spacer()
                            content
                            Spacer()
                        }
                        .background(GeometryReader { inner in
                            Color.clear
                                .onAppear { contentWidth = inner.size.width }
                                .onChange(of: poller.lastUpdated) { _, _ in
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        contentWidth = inner.size.width
                                    }
                                }
                        })
                    }
                }
                .onAppear {
                    containerWidth = geo.size.width
                    startScrolling()
                }
                .onChange(of: geo.size.width) { _, newWidth in
                    containerWidth = newWidth
                }
                .onDisappear {
                    scrollTimer?.invalidate()
                }
            }
            .clipped()
        }
    }

    // MARK: - Ticker Content

    private var tickerContent: some View {
        HStack(spacing: 0) {
            ForEach(Array(tickerGames.enumerated()), id: \.element.id) { index, game in
                TickerGameCard(event: game, mode: cardMode, now: now, tickerHeight: tickerSize, onDetach: {
                    onDetachGame?(game)
                })

                if index < tickerGames.count - 1 {
                    TickerDivider()
                }
            }
            if needsScroll {
                Spacer().frame(width: 80)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Timers

    private func startClockRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            now = Date()
        }
    }

    private func startScrolling() {
        scrollTimer?.invalidate()
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { _ in
            guard needsScroll else {
                scrollOffset = 0
                return
            }
            if isHovering { return }
            scrollOffset += 0.7
            if scrollOffset >= contentWidth + 80 {
                scrollOffset = 0
            }
        }
    }
}

// MARK: - Card Mode

enum CardMode {
    case expanded
    case medium
    case compact
}

// MARK: - Game Card

struct TickerGameCard: View {
    let event: Event
    let mode: CardMode
    let now: Date
    let tickerHeight: Double
    var onDetach: (() -> Void)?
    @State private var isHovered = false

    private var isClose: Bool {
        guard event.isLive, let diff = event.scoreDifference else { return false }
        return diff <= 5
    }

    private var awayColor: Color {
        Color(hex: event.awayCompetitor?.team.color) ?? .blue
    }
    private var homeColor: Color {
        Color(hex: event.homeCompetitor?.team.color) ?? .red
    }

    private var scaleFactor: Double {
        tickerHeight / 38.0
    }

    var body: some View {
        Group {
            switch mode {
            case .expanded: expandedCard
            case .medium: mediumCard
            case .compact: compactCard
            }
        }
        .padding(.horizontal, mode == .compact ? 4 : 6)
        .padding(.vertical, 3)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(cardBackground)
                // Team color gradient at bottom
                HStack(spacing: 0) {
                    awayColor.opacity(0.15)
                    homeColor.opacity(0.15)
                }
                .frame(height: 2)
                .clipShape(RoundedRectangle(cornerRadius: 1))
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isHovered ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .padding(.horizontal, 3)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button("Detach as Widget") {
                onDetach?()
            }
        }
    }

    // MARK: - Expanded Card (1-2 games)

    private var expandedCard: some View {
        HStack(spacing: 12) {
            if event.isLive {
                pulsingLiveIndicator
            }

            // Away team
            expandedTeamView(event.awayCompetitor, isWinner: isWinner(event.awayCompetitor))

            // Center score block
            VStack(spacing: 1) {
                if event.isLive || event.isFinal {
                    Text(scoreText)
                        .font(.system(size: 16 * scaleFactor, weight: .heavy, design: .rounded))
                        .foregroundStyle(isClose ? .red : .primary)
                }

                if event.isLive {
                    liveTimePill
                } else if event.isFinal {
                    Text(event.status.type.detail ?? "Final")
                        .font(.system(size: 8 * scaleFactor, weight: .bold))
                        .foregroundStyle(.secondary)
                } else if let date = event.startDate {
                    VStack(spacing: 0) {
                        Text(DateFormatters.timeOnly.string(from: date))
                            .font(.system(size: 13 * scaleFactor, weight: .semibold))
                        Text(timeUntilText(date))
                            .font(.system(size: 8 * scaleFactor, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minWidth: 70)

            // Home team
            expandedTeamView(event.homeCompetitor, isWinner: isWinner(event.homeCompetitor))

            // Metadata
            VStack(alignment: .trailing, spacing: 2) {
                if let broadcast = event.competition?.broadcasts?.first?.names?.first {
                    Text(broadcast)
                        .font(.system(size: 9 * scaleFactor, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                if let round = event.roundName {
                    Text(round)
                        .font(.system(size: 8 * scaleFactor, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if event.isUpset {
                    HStack(spacing: 2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 7 * scaleFactor))
                        Text("UPSET")
                            .font(.system(size: 7 * scaleFactor, weight: .heavy))
                    }
                    .foregroundStyle(.orange)
                }
            }
        }
    }

    private func expandedTeamView(_ competitor: Competitor?, isWinner: Bool) -> some View {
        HStack(spacing: 6) {
            teamLogo(competitor, size: 24 * scaleFactor)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 3) {
                    if let seed = competitor?.seed {
                        Text("(\(seed))")
                            .font(.system(size: 9 * scaleFactor, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(competitor?.team.displayName ?? "TBD")
                        .font(.system(size: 12 * scaleFactor, weight: isWinner ? .bold : .semibold))
                        .lineLimit(1)
                }
                if let record = competitor?.records?.first(where: { $0.type == "total" })?.summary {
                    Text(record)
                        .font(.system(size: 9 * scaleFactor))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Medium Card (3-5 games)

    private var mediumCard: some View {
        HStack(spacing: 0) {
            if event.isLive {
                pulsingLiveIndicator
            }

            // Away team
            teamLogo(event.awayCompetitor, size: 20 * scaleFactor)
            if let seed = event.awayCompetitor?.seed {
                Text("\(seed)")
                    .font(.system(size: 8 * scaleFactor, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
            Text(event.awayCompetitor?.team.abbreviation ?? "—")
                .font(.system(size: 12 * scaleFactor, weight: isWinner(event.awayCompetitor) ? .bold : .medium))
                .padding(.leading, 3)

            // Score / time
            VStack(spacing: 0) {
                if event.isLive || event.isFinal {
                    Text(scoreText)
                        .font(.system(size: 14 * scaleFactor, weight: .heavy, design: .rounded))
                        .foregroundStyle(isClose ? .red : .primary)
                }

                if event.isLive {
                    liveTimePill
                } else if event.isFinal {
                    Text(event.status.type.shortDetail ?? "Final")
                        .font(.system(size: 7 * scaleFactor, weight: .bold))
                        .foregroundStyle(.secondary)
                } else if let date = event.startDate {
                    VStack(spacing: 0) {
                        Text(DateFormatters.timeOnly.string(from: date))
                            .font(.system(size: 11 * scaleFactor, weight: .semibold))
                        Text("vs")
                            .font(.system(size: 7 * scaleFactor, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(minWidth: 58)
            .padding(.horizontal, 4)

            // Home team
            Text(event.homeCompetitor?.team.abbreviation ?? "—")
                .font(.system(size: 12 * scaleFactor, weight: isWinner(event.homeCompetitor) ? .bold : .medium))
                .padding(.trailing, 3)
            if let seed = event.homeCompetitor?.seed {
                Text("\(seed)")
                    .font(.system(size: 8 * scaleFactor, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 2)
            }
            teamLogo(event.homeCompetitor, size: 20 * scaleFactor)

            // Badge
            periodOrUpsetBadge
        }
    }

    // MARK: - Compact Card (6+ games, scrolling)

    private var compactCard: some View {
        HStack(spacing: 0) {
            if event.isLive {
                Circle()
                    .fill(.red)
                    .frame(width: 5, height: 5)
                    .padding(.trailing, 3)
            }

            // Away
            teamLogo(event.awayCompetitor, size: 16 * scaleFactor)
            if let seed = event.awayCompetitor?.seed {
                Text("\(seed)")
                    .font(.system(size: 7 * scaleFactor, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 1)
            }
            Text(event.awayCompetitor?.team.abbreviation ?? "—")
                .font(.system(size: 11 * scaleFactor, weight: isWinner(event.awayCompetitor) ? .bold : .medium))
                .padding(.leading, 2)

            // Score / time
            VStack(spacing: 0) {
                if event.isLive || event.isFinal {
                    Text(scoreText)
                        .font(.system(size: 12 * scaleFactor, weight: .heavy, design: .rounded))
                        .foregroundStyle(isClose ? .red : .primary)
                    if event.isLive {
                        Text(shortTimeText)
                            .font(.system(size: 7 * scaleFactor, weight: .bold, design: .monospaced))
                            .foregroundStyle(.red.opacity(0.9))
                    } else {
                        Text("F")
                            .font(.system(size: 7 * scaleFactor, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                } else if let date = event.startDate {
                    Text(DateFormatters.timeOnly.string(from: date))
                        .font(.system(size: 10 * scaleFactor, weight: .semibold))
                }
            }
            .frame(minWidth: 48)
            .padding(.horizontal, 3)

            // Home
            Text(event.homeCompetitor?.team.abbreviation ?? "—")
                .font(.system(size: 11 * scaleFactor, weight: isWinner(event.homeCompetitor) ? .bold : .medium))
                .padding(.trailing, 2)
            if let seed = event.homeCompetitor?.seed {
                Text("\(seed)")
                    .font(.system(size: 7 * scaleFactor, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 1)
            }
            teamLogo(event.homeCompetitor, size: 16 * scaleFactor)

            // Period badge
            if event.isLive {
                Text(shortPeriodText)
                    .font(.system(size: 7 * scaleFactor, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(isClose ? .red : .red.opacity(0.7)))
                    .padding(.leading, 3)
            }
        }
    }

    // MARK: - Shared Components

    private func teamLogo(_ competitor: Competitor?, size: CGFloat) -> some View {
        Group {
            if let logoURL = competitor?.team.logoURL {
                AsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fit).frame(width: size, height: size)
                    default:
                        Image(systemName: "basketball.fill")
                            .font(.system(size: size * 0.6))
                            .foregroundStyle(.secondary)
                            .frame(width: size, height: size)
                    }
                }
            } else {
                Image(systemName: "basketball.fill")
                    .font(.system(size: size * 0.6))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
            }
        }
    }

    private var pulsingLiveIndicator: some View {
        Circle()
            .fill(.red)
            .frame(width: 6, height: 6)
            .overlay(
                Circle()
                    .stroke(.red.opacity(0.4), lineWidth: 2)
                    .frame(width: 10, height: 10)
            )
            .padding(.trailing, 4)
    }

    /// Shows "2nd Half 4:32" or "OT 1:15" as a styled pill
    private var liveTimePill: some View {
        Text(quarterTimeText)
            .font(.system(size: max(7, 8 * scaleFactor), weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(isClose ? .red : .red.opacity(0.75)))
    }

    @ViewBuilder
    private var periodOrUpsetBadge: some View {
        if event.isLive && isClose {
            Text("CLOSE")
                .font(.system(size: 7 * scaleFactor, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(.red))
                .padding(.leading, 4)
        } else if event.isLive {
            Text(shortPeriodText)
                .font(.system(size: 7 * scaleFactor, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(.red.opacity(0.8)))
                .padding(.leading, 4)
        } else if event.isUpset {
            HStack(spacing: 1) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 6))
                Text("UPSET")
                    .font(.system(size: 7 * scaleFactor, weight: .heavy))
            }
            .foregroundStyle(.orange)
            .padding(.leading, 4)
        } else if let broadcast = event.competition?.broadcasts?.first?.names?.first {
            Text(broadcast)
                .font(.system(size: 8 * scaleFactor, weight: .medium))
                .foregroundStyle(.orange.opacity(0.8))
                .padding(.leading, 4)
        }
    }

    // MARK: - Helpers

    private var cardBackground: Color {
        if isClose { return .red.opacity(0.08) }
        if event.isLive { return .red.opacity(0.04) }
        return .clear
    }

    private var scoreText: String {
        "\(event.awayCompetitor?.score ?? "0") - \(event.homeCompetitor?.score ?? "0")"
    }

    private var quarterTimeText: String {
        let period = event.status.period
        let clock = event.status.displayClock ?? ""
        let periodName: String
        if period > 2 { periodName = period == 3 ? "OT" : "\(period - 2)OT" }
        else { periodName = period == 1 ? "1st Half" : "2nd Half" }
        return clock.isEmpty ? periodName : "\(periodName) \(clock)"
    }

    private var shortTimeText: String {
        let period = event.status.period
        let clock = event.status.displayClock ?? ""
        let p: String
        if period > 2 { p = period == 3 ? "OT" : "\(period-2)OT" }
        else { p = period == 1 ? "1H" : "2H" }
        return clock.isEmpty ? p : "\(p) \(clock)"
    }

    private var shortPeriodText: String {
        let period = event.status.period
        if period > 2 { return period == 3 ? "OT" : "\(period-2)OT" }
        return period == 1 ? "1H" : "2H"
    }

    private func timeUntilText(_ date: Date) -> String {
        let diff = date.timeIntervalSince(now)
        if diff < 0 { return "started" }
        let hours = Int(diff) / 3600
        let mins = (Int(diff) % 3600) / 60
        return hours > 0 ? "in \(hours)h \(mins)m" : "in \(mins)m"
    }

    private func isWinner(_ competitor: Competitor?) -> Bool {
        guard event.isFinal,
              let competitor,
              let other = (competitor.homeAway == "home" ? event.awayCompetitor : event.homeCompetitor),
              let score = competitor.scoreInt,
              let otherScore = other.scoreInt else { return false }
        return score > otherScore
    }
}

// MARK: - Divider

struct TickerDivider: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 2)
    }
}

// MARK: - Visual Effect Blur

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
