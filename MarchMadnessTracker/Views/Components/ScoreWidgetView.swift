import SwiftUI

/// A floating score widget styled like an official Apple desktop widget
struct ScoreWidgetView: View {
    let eventId: String
    var poller: ScorePoller
    var onClose: (() -> Void)?
    @State private var now = Date()
    @State private var isHovered = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var event: Event? {
        poller.games.first { $0.id == eventId }
    }

    private var awayColor: Color {
        Color(hex: event?.awayCompetitor?.team.color) ?? .blue
    }
    private var homeColor: Color {
        Color(hex: event?.homeCompetitor?.team.color) ?? .red
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let event {
                widgetContent(event)
            } else {
                emptyState
            }

            // Close button — only visible on hover
            if isHovered {
                Button {
                    onClose?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(8)
                .transition(.opacity)
            }
        }
        .frame(width: 280, height: 140)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.05)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
        .onReceive(timer) { _ in now = Date() }
    }

    // MARK: - Widget Content

    private func widgetContent(_ event: Event) -> some View {
        VStack(spacing: 0) {
            // Top: round label
            HStack {
                if event.isLive {
                    HStack(spacing: 4) {
                        Circle().fill(.red).frame(width: 6, height: 6)
                        Text("LIVE")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.red)
                    }
                }
                Spacer()
                if let round = event.roundName {
                    Text(round)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Spacer()

            // Center: Teams + Score
            HStack(spacing: 0) {
                // Away team
                appleTeamView(event.awayCompetitor, isWinner: isWinner(event.awayCompetitor, event: event))
                    .frame(maxWidth: .infinity)

                // Score center
                VStack(spacing: 3) {
                    if event.isLive || event.isFinal {
                        HStack(spacing: 6) {
                            Text(event.awayCompetitor?.score ?? "0")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(isWinner(event.awayCompetitor, event: event) ? .primary : .secondary)
                                .contentTransition(.numericText())
                            Text(event.homeCompetitor?.score ?? "0")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(isWinner(event.homeCompetitor, event: event) ? .primary : .secondary)
                                .contentTransition(.numericText())
                        }
                    }

                    if event.isLive {
                        appleTimePill(event)
                    } else if event.isFinal {
                        Text(event.status.type.detail ?? "Final")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else if let date = event.startDate {
                        Text(DateFormatters.timeOnly.string(from: date))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                }
                .frame(minWidth: 90)

                // Home team
                appleTeamView(event.homeCompetitor, isWinner: isWinner(event.homeCompetitor, event: event))
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)

            Spacer()

            // Bottom: broadcast / upset
            HStack {
                if event.isUpset {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                        Text("UPSET")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(.orange)
                }
                Spacer()
                if let broadcast = event.competition?.broadcasts?.first?.names?.first {
                    Text(broadcast)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private func appleTeamView(_ competitor: Competitor?, isWinner: Bool) -> some View {
        VStack(spacing: 4) {
            // Logo with team color ring
            ZStack {
                Circle()
                    .fill(Color(hex: competitor?.team.color)?.opacity(0.15) ?? .clear)
                    .frame(width: 40, height: 40)

                if let url = competitor?.team.logoURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().aspectRatio(contentMode: .fit).frame(width: 28, height: 28)
                        } else {
                            Image(systemName: "basketball.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Team name
            VStack(spacing: 0) {
                if let seed = competitor?.seed {
                    Text("#\(seed)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                Text(competitor?.team.abbreviation ?? "TBD")
                    .font(.system(size: 12, weight: isWinner ? .bold : .semibold, design: .rounded))
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func appleTimePill(_ event: Event) -> some View {
        let period = event.status.period
        let clock = event.status.displayClock ?? ""
        let periodName: String = {
            if period > 2 { return period == 3 ? "OT" : "\(period-2)OT" }
            return period == 1 ? "1st Half" : "2nd Half"
        }()

        Text("\(periodName)  \(clock)")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(.red.gradient))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "basketball")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Game unavailable")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Button("Close") { onClose?() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private func isWinner(_ competitor: Competitor?, event: Event) -> Bool {
        guard let competitor,
              let other = (competitor.homeAway == "home" ? event.awayCompetitor : event.homeCompetitor),
              let score = competitor.scoreInt,
              let otherScore = other.scoreInt else { return false }
        return score > otherScore
    }
}
