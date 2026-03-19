import SwiftUI

struct BracketMatchupView: View {
    let event: Event

    private var awayColor: Color {
        Color(hex: event.awayCompetitor?.team.color) ?? .blue
    }

    private var homeColor: Color {
        Color(hex: event.homeCompetitor?.team.color) ?? .red
    }

    var body: some View {
        Button {
            NotificationCenter.default.post(
                name: .openGameDetail,
                object: nil,
                userInfo: ["eventId": event.id]
            )
        } label: {
            HStack(spacing: 0) {
                // Team color gradient edge
                VStack(spacing: 0) {
                    awayColor.frame(width: 3)
                    homeColor.frame(width: 3)
                }
                .clipShape(RoundedRectangle(cornerRadius: 1))

                VStack(spacing: 0) {
                    bracketTeamRow(
                        competitor: event.awayCompetitor,
                        isWinner: event.isFinal && isWinner(event.awayCompetitor)
                    )
                    Divider().padding(.leading, 40)
                    bracketTeamRow(
                        competitor: event.homeCompetitor,
                        isWinner: event.isFinal && isWinner(event.homeCompetitor)
                    )

                    // Status
                    HStack(spacing: 4) {
                        if event.isLive {
                            Circle().fill(.red).frame(width: 5, height: 5)
                            Text(event.status.type.shortDetail ?? "Live")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        } else if event.isFinal {
                            Text("Final")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else if let date = event.startDate {
                            Text(DateFormatters.timeOnly.string(from: date))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if event.isUpset {
                            HStack(spacing: 2) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 7))
                                Text("UPSET")
                                    .font(.system(size: 7, weight: .heavy))
                            }
                            .foregroundStyle(.orange)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(event.isLive ? Color.red.opacity(0.04) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(event.isUpset ? Color.orange.opacity(0.4) : Color(nsColor: .separatorColor), lineWidth: event.isUpset ? 1 : 0.5)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func bracketTeamRow(competitor: Competitor?, isWinner: Bool) -> some View {
        HStack(spacing: 6) {
            if let seed = competitor?.seed {
                Text("\(seed)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .trailing)
            } else {
                Spacer().frame(width: 16)
            }

            TeamLogoView(url: competitor?.team.logoURL, size: 16)

            Text(competitor?.team.abbreviation ?? "TBD")
                .font(.caption)
                .fontWeight(isWinner ? .bold : .regular)
                .lineLimit(1)

            Spacer()

            if let score = competitor?.score {
                Text(score)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(isWinner ? .bold : .regular)
            }

            if isWinner {
                Image(systemName: "chevron.left")
                    .font(.system(size: 8))
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
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
