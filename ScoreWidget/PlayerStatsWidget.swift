import WidgetKit
import SwiftUI

// MARK: - Player Stats Widget

struct PlayerStatsProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlayerStatsEntry {
        PlayerStatsEntry(date: Date(), topPerformers: samplePerformers)
    }

    func getSnapshot(in context: Context, completion: @escaping (PlayerStatsEntry) -> Void) {
        if context.isPreview {
            completion(PlayerStatsEntry(date: Date(), topPerformers: samplePerformers))
            return
        }
        Task {
            let performers = await fetchTopPerformers()
            completion(PlayerStatsEntry(date: Date(), topPerformers: performers.isEmpty ? samplePerformers : performers))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlayerStatsEntry>) -> Void) {
        Task {
            let performers = await fetchTopPerformers()
            let entry = PlayerStatsEntry(date: Date(), topPerformers: performers.isEmpty ? samplePerformers : performers)
            let hasLive = performers.contains { $0.isLive }
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: hasLive ? 2 : 15, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private func fetchTopPerformers() async -> [TopPerformer] {
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/scoreboard?groups=100&limit=100") else {
            return []
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let events = json?["events"] as? [[String: Any]] else { return [] }

            var performers: [TopPerformer] = []

            for event in events {
                guard let comps = event["competitions"] as? [[String: Any]],
                      let comp = comps.first,
                      let competitors = comp["competitors"] as? [[String: Any]],
                      let status = event["status"] as? [String: Any],
                      let statusType = status["type"] as? [String: Any],
                      let state = statusType["state"] as? String else { continue }

                let isLive = state == "in"
                let isFinal = state == "post"
                guard isLive || isFinal else { continue }

                for competitor in competitors {
                    guard let team = competitor["team"] as? [String: Any],
                          let leaders = competitor["leaders"] as? [[String: Any]] else { continue }

                    let teamAbbr = team["abbreviation"] as? String ?? "?"
                    let teamColor = team["color"] as? String
                    let teamLogo = team["logo"] as? String

                    // Get each stat leader
                    for leader in leaders {
                        guard let statName = leader["name"] as? String,
                              let leaderList = leader["leaders"] as? [[String: Any]],
                              let topLeader = leaderList.first,
                              let athlete = topLeader["athlete"] as? [String: Any],
                              let displayValue = topLeader["displayValue"] as? String,
                              let value = topLeader["value"] as? Double else { continue }

                        // Skip "rating" stat - it's a composite
                        if statName == "rating" { continue }

                        let playerName = athlete["shortName"] as? String ?? "Unknown"
                        let headshot = athlete["headshot"] as? String

                        performers.append(TopPerformer(
                            playerName: playerName,
                            teamAbbreviation: teamAbbr,
                            teamColor: teamColor,
                            teamLogo: teamLogo,
                            headshotURL: headshot,
                            statName: statName,
                            statDisplayName: leader["shortDisplayName"] as? String ?? statName,
                            statValue: displayValue,
                            statNumeric: value,
                            isLive: isLive
                        ))
                    }
                }
            }

            // Sort by stat value (highest first), grouping by stat type
            // Return top scorers, rebounders, and assist leaders
            let scorers = performers.filter { $0.statName == "points" }.sorted { $0.statNumeric > $1.statNumeric }
            let rebounders = performers.filter { $0.statName == "rebounds" }.sorted { $0.statNumeric > $1.statNumeric }
            let assisters = performers.filter { $0.statName == "assists" }.sorted { $0.statNumeric > $1.statNumeric }

            // Interleave: top scorer, top rebounder, top assister, repeat
            var result: [TopPerformer] = []
            let maxCount = max(scorers.count, rebounders.count, assisters.count)
            for i in 0..<maxCount {
                if i < scorers.count { result.append(scorers[i]) }
                if i < rebounders.count { result.append(rebounders[i]) }
                if i < assisters.count { result.append(assisters[i]) }
            }
            return result
        } catch {
            return []
        }
    }
}

// MARK: - Data Model

struct TopPerformer: Identifiable {
    let id = UUID()
    let playerName: String
    let teamAbbreviation: String
    let teamColor: String?
    let teamLogo: String?
    let headshotURL: String?
    let statName: String
    let statDisplayName: String
    let statValue: String
    let statNumeric: Double
    let isLive: Bool
}

struct PlayerStatsEntry: TimelineEntry {
    let date: Date
    let topPerformers: [TopPerformer]

    var hasLive: Bool { topPerformers.contains { $0.isLive } }
}

// MARK: - Widget Definition

struct PlayerStatsWidget: Widget {
    let kind: String = "PlayerStatsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlayerStatsProvider()) { entry in
            PlayerStatsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Player Stats")
        .description("Top performers in March Madness — points, rebounds, assists")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Widget View

struct PlayerStatsWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: PlayerStatsEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        default:
            largeView
        }
    }

    // MARK: - Small: Top scorer only

    private var smallView: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                Text("Top Performer")
                    .font(.system(size: 9, weight: .bold))
                Spacer()
            }

            if let top = entry.topPerformers.first(where: { $0.statName == "points" }) {
                Spacer(minLength: 0)
                playerCard(top, size: .small)
                Spacer(minLength: 0)
            } else {
                Spacer()
                Text("No games")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(8)
    }

    // MARK: - Medium: Top 3 stat leaders

    private var mediumView: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.blue)
                Text("March Madness Leaders")
                    .font(.system(size: 10, weight: .bold))
                Spacer()
                if entry.hasLive {
                    HStack(spacing: 2) {
                        Circle().fill(.red).frame(width: 4, height: 4)
                        Text("LIVE")
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(.red)
                    }
                }
            }

            HStack(spacing: 6) {
                // Top scorer
                if let scorer = entry.topPerformers.first(where: { $0.statName == "points" }) {
                    statColumn(scorer, icon: "flame.fill", color: .orange)
                }
                // Top rebounder
                if let rebounder = entry.topPerformers.first(where: { $0.statName == "rebounds" }) {
                    statColumn(rebounder, icon: "arrow.up.circle.fill", color: .green)
                }
                // Top assists
                if let assister = entry.topPerformers.first(where: { $0.statName == "assists" }) {
                    statColumn(assister, icon: "arrow.right.circle.fill", color: .purple)
                }
            }
        }
        .padding(8)
    }

    // MARK: - Large: Full leaderboard

    private var largeView: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.blue)
                Text("March Madness Player Stats")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                if entry.hasLive {
                    HStack(spacing: 2) {
                        Circle().fill(.red).frame(width: 5, height: 5)
                        Text("LIVE")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.bottom, 2)

            // Scoring leaders
            statSection(
                title: "Scoring",
                icon: "flame.fill",
                color: .orange,
                performers: Array(entry.topPerformers.filter { $0.statName == "points" }.prefix(5))
            )

            Divider()

            // Rebound leaders
            statSection(
                title: "Rebounds",
                icon: "arrow.up.circle.fill",
                color: .green,
                performers: Array(entry.topPerformers.filter { $0.statName == "rebounds" }.prefix(5))
            )

            Divider()

            // Assist leaders
            statSection(
                title: "Assists",
                icon: "arrow.right.circle.fill",
                color: .purple,
                performers: Array(entry.topPerformers.filter { $0.statName == "assists" }.prefix(5))
            )

            Spacer(minLength: 0)
        }
        .padding(8)
    }

    // MARK: - Components

    private func playerCard(_ performer: TopPerformer, size: CardSize) -> some View {
        VStack(spacing: 4) {
            Text(performer.statValue)
                .font(.system(size: size == .small ? 28 : 20, weight: .heavy, design: .rounded))
                .foregroundStyle(colorForStat(performer.statName))

            Text(performer.statDisplayName.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)

            Text(performer.playerName)
                .font(.system(size: size == .small ? 12 : 10, weight: .semibold))
                .lineLimit(1)

            HStack(spacing: 3) {
                teamColorDot(performer.teamColor)
                Text(performer.teamAbbreviation)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                if performer.isLive {
                    Circle().fill(.red).frame(width: 4, height: 4)
                }
            }
        }
    }

    private func statColumn(_ performer: TopPerformer, icon: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)

            Text(performer.statValue)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(color)

            Text(performer.statDisplayName.uppercased())
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.secondary)

            Text(performer.playerName)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)

            HStack(spacing: 2) {
                teamColorDot(performer.teamColor)
                Text(performer.teamAbbreviation)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                if performer.isLive {
                    Circle().fill(.red).frame(width: 3, height: 3)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func statSection(title: String, icon: String, color: Color, performers: [TopPerformer]) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                    .foregroundStyle(color)
                Text(title.uppercased())
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(color)
                Spacer()
            }

            ForEach(Array(performers.enumerated()), id: \.element.id) { idx, performer in
                HStack(spacing: 4) {
                    Text("\(idx + 1)")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)

                    teamColorDot(performer.teamColor)

                    Text(performer.playerName)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)

                    Text(performer.teamAbbreviation)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if performer.isLive {
                        Circle().fill(.red).frame(width: 3, height: 3)
                    }

                    Text(performer.statValue)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func teamColorDot(_ hex: String?) -> some View {
        Circle()
            .fill(Color(hex: hex) ?? .gray)
            .frame(width: 6, height: 6)
    }

    private func colorForStat(_ stat: String) -> Color {
        switch stat {
        case "points": return .orange
        case "rebounds": return .green
        case "assists": return .purple
        default: return .blue
        }
    }

    enum CardSize { case small, medium }
}

// MARK: - Color hex extension

private extension Color {
    init?(hex: String?) {
        guard let hex = hex else { return nil }
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let int = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Sample Data

private let samplePerformers: [TopPerformer] = [
    TopPerformer(playerName: "C. Cooper", teamAbbreviation: "MSU", teamColor: "18453B",
                 teamLogo: nil, headshotURL: nil, statName: "points",
                 statDisplayName: "Pts", statValue: "28", statNumeric: 28, isLive: true),
    TopPerformer(playerName: "J. Fears", teamAbbreviation: "MSU", teamColor: "18453B",
                 teamLogo: nil, headshotURL: nil, statName: "assists",
                 statDisplayName: "Ast", statValue: "11", statNumeric: 11, isLive: true),
    TopPerformer(playerName: "T. Anderson", teamAbbreviation: "HPU", teamColor: "330072",
                 teamLogo: nil, headshotURL: nil, statName: "rebounds",
                 statDisplayName: "Reb", statValue: "11", statNumeric: 11, isLive: false),
    TopPerformer(playerName: "N. Boyd", teamAbbreviation: "WIS", teamColor: "C5050C",
                 teamLogo: nil, headshotURL: nil, statName: "points",
                 statDisplayName: "Pts", statValue: "27", statNumeric: 27, isLive: false),
    TopPerformer(playerName: "R. Martin", teamAbbreviation: "HPU", teamColor: "330072",
                 teamLogo: nil, headshotURL: nil, statName: "points",
                 statDisplayName: "Pts", statValue: "23", statNumeric: 23, isLive: false),
    TopPerformer(playerName: "R. Martin", teamAbbreviation: "HPU", teamColor: "330072",
                 teamLogo: nil, headshotURL: nil, statName: "assists",
                 statDisplayName: "Ast", statValue: "10", statNumeric: 10, isLive: false),
]
