import SwiftUI

struct GameDetailView: View {
    let event: Event
    var onCreateWidget: (() -> Void)?
    @State private var now = Date()
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    private var awayColor: Color {
        Color(hex: event.awayCompetitor?.team.color) ?? .blue
    }

    private var homeColor: Color {
        Color(hex: event.homeCompetitor?.team.color) ?? .red
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top gradient bar with team colors
            HStack(spacing: 0) {
                awayColor.frame(height: 4)
                homeColor.frame(height: 4)
            }

            // Header: round + status + widget button
            HStack {
                if let round = event.roundName {
                    Text(round)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                if let region = event.regionName {
                    Text("- \(region) Region")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if event.isUpset {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text("UPSET")
                            .font(.system(size: 9, weight: .heavy))
                    }
                    .foregroundStyle(.orange)
                }

                // Pin as Widget button
                Button {
                    if let onCreateWidget {
                        onCreateWidget()
                    } else {
                        NotificationCenter.default.post(
                            name: .createGameWidget,
                            object: nil,
                            userInfo: ["eventId": event.id]
                        )
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                        Text("Pin Widget")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)

            // Main matchup
            HStack(spacing: 0) {
                // Away team
                teamDetailBlock(event.awayCompetitor, alignment: .trailing)
                    .frame(maxWidth: .infinity)

                // Center score
                VStack(spacing: 2) {
                    if event.isLive || event.isFinal {
                        HStack(spacing: 8) {
                            Text(event.awayCompetitor?.score ?? "0")
                                .font(.system(size: 32, weight: .heavy, design: .rounded))
                                .foregroundStyle(isWinner(event.awayCompetitor) ? .primary : .secondary)
                            Text("-")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(.tertiary)
                            Text(event.homeCompetitor?.score ?? "0")
                                .font(.system(size: 32, weight: .heavy, design: .rounded))
                                .foregroundStyle(isWinner(event.homeCompetitor) ? .primary : .secondary)
                        }
                    }

                    if event.isLive {
                        liveStatusPill
                    } else if event.isFinal {
                        Text(event.status.type.detail ?? "Final")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                    } else if let date = event.startDate {
                        VStack(spacing: 2) {
                            Text(DateFormatters.timeOnly.string(from: date))
                                .font(.system(size: 20, weight: .semibold))
                            Text(DateFormatters.dayHeader.string(from: date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(minWidth: 120)
                .padding(.horizontal, 8)

                // Home team
                teamDetailBlock(event.homeCompetitor, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider().padding(.horizontal, 16)

            // Game details
            VStack(spacing: 8) {
                if let broadcast = event.competition?.broadcasts?.first?.names?.first {
                    detailRow(icon: "tv", label: "Broadcast", value: broadcast)
                }
                if let venue = event.competition?.venue {
                    let location = [venue.fullName, venue.city, venue.state].compactMap { $0 }.joined(separator: ", ")
                    if !location.isEmpty {
                        detailRow(icon: "mappin.circle", label: "Venue", value: location)
                    }
                }
                if event.isUpset, let magnitude = event.upsetMagnitude {
                    let underdogName = event.underdog?.team.displayName ?? "Underdog"
                    detailRow(icon: "exclamationmark.triangle", label: "Upset Alert", value: "\(underdogName) (+\(magnitude) seed diff)")
                }
            }
            .padding(16)

            Spacer()
        }
        .frame(width: 400, height: 280)
        .onReceive(timer) { _ in
            now = Date()
        }
    }

    private func teamDetailBlock(_ competitor: Competitor?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            // Logo
            if let url = competitor?.team.logoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fit).frame(width: 48, height: 48)
                    default:
                        Image(systemName: "basketball.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                            .frame(width: 48, height: 48)
                    }
                }
            }

            // Seed + Name
            HStack(spacing: 3) {
                if let seed = competitor?.seed {
                    Text("(\(seed))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(competitor?.team.displayName ?? "TBD")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }

            // Record
            if let record = competitor?.records?.first(where: { $0.type == "total" })?.summary {
                Text(record)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var liveStatusPill: some View {
        let period = event.status.period
        let clock = event.status.displayClock ?? ""
        let periodName: String = {
            if period > 2 { return period == 3 ? "OT" : "\(period-2)OT" }
            return period == 1 ? "1st Half" : "2nd Half"
        }()

        HStack(spacing: 4) {
            Circle().fill(.red).frame(width: 6, height: 6)
            Text("\(periodName) \(clock)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(.red.opacity(0.1)))
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
        }
    }

    private func isWinner(_ competitor: Competitor?) -> Bool {
        guard let competitor,
              let other = (competitor.homeAway == "home" ? event.awayCompetitor : event.homeCompetitor),
              let score = competitor.scoreInt,
              let otherScore = other.scoreInt else { return false }
        return score > otherScore
    }
}
