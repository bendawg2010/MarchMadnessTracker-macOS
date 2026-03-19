import SwiftUI

struct GameRowView: View {
    let event: Event
    @State private var isHovered = false

    private var awayColor: Color {
        Color(hex: event.awayCompetitor?.team.color) ?? .blue
    }

    private var homeColor: Color {
        Color(hex: event.homeCompetitor?.team.color) ?? .red
    }

    var body: some View {
        HStack(spacing: 0) {
            // Main clickable game row — opens detail window
            Button {
                NotificationCenter.default.post(
                    name: .openGameDetail,
                    object: nil,
                    userInfo: ["eventId": event.id]
                )
            } label: {
                HStack(spacing: 0) {
                    // Team color accent bar
                    VStack(spacing: 0) {
                        awayColor.frame(width: 3)
                        homeColor.frame(width: 3)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .padding(.vertical, 4)

                    VStack(spacing: 6) {
                        teamRow(
                            competitor: event.awayCompetitor,
                            isWinner: event.isFinal && isWinner(event.awayCompetitor)
                        )
                        teamRow(
                            competitor: event.homeCompetitor,
                            isWinner: event.isFinal && isWinner(event.homeCompetitor)
                        )

                        // Status line
                        HStack(spacing: 4) {
                            statusView

                            if event.isUpset {
                                upsetBadge
                            }

                            Spacer()

                            if let broadcast = event.competition?.broadcasts?.first?.names?.first {
                                Text(broadcast)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Image(systemName: "chevron.right")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .buttonStyle(.plain)

            // Widget pin button — separate from main row button so taps don't conflict
            Button {
                NotificationCenter.default.post(
                    name: .createGameWidget,
                    object: nil,
                    userInfo: ["eventId": event.id]
                )
            } label: {
                VStack {
                    Spacer()
                    Image(systemName: "macwindow.badge.plus")
                        .font(.system(size: 12))
                        .foregroundStyle(isHovered ? Color.accentColor : Color.clear)
                    Text("Widget")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(isHovered ? Color.accentColor : Color.clear)
                    Spacer()
                }
                .frame(width: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Pin as floating widget")
        }
        .background(backgroundStyle)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 8)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
    }

    @ViewBuilder
    private var backgroundStyle: some View {
        if event.isLive && event.isUpset {
            Color.orange.opacity(0.06)
        } else if event.isLive {
            Color.red.opacity(0.04)
        } else if event.isFinal && event.isUpset {
            Color.orange.opacity(0.03)
        } else {
            Color.clear
        }
    }

    private var upsetBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 7))
            Text("UPSET")
                .font(.system(size: 7, weight: .heavy))
            if let mag = event.upsetMagnitude, mag >= 5 {
                Text("+\(mag)")
                    .font(.system(size: 7, weight: .bold))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(.orange))
    }

    private func teamRow(competitor: Competitor?, isWinner: Bool) -> some View {
        HStack(spacing: 8) {
            if let seed = competitor?.seed {
                Text("\(seed)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .trailing)
            } else {
                Spacer().frame(width: 16)
            }

            TeamLogoView(url: competitor?.team.logoURL, size: 20)

            Text(competitor?.team.abbreviation ?? "TBD")
                .font(.system(.subheadline, weight: isWinner ? .bold : .regular))
                .lineLimit(1)

            if let record = competitor?.records?.first(where: { $0.type == "total" })?.summary {
                Text("(\(record))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if let score = competitor?.score {
                Text(score)
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(isWinner ? .bold : .regular)
            }

            if isWinner {
                Image(systemName: "chevron.left")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if event.isLive {
            HStack(spacing: 4) {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
                Text(event.status.type.shortDetail ?? event.status.type.detail ?? "Live")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.red)
            }
        } else if event.isFinal {
            Text(event.status.type.detail ?? "Final")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if let date = event.startDate {
            Text(DateFormatters.timeOnly.string(from: date))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func isWinner(_ competitor: Competitor?) -> Bool {
        guard let competitor, let other = (competitor.homeAway == "home" ? event.awayCompetitor : event.homeCompetitor) else {
            return false
        }
        guard let score = competitor.scoreInt, let otherScore = other.scoreInt else { return false }
        return score > otherScore
    }
}
