import WidgetKit
import SwiftUI

// MARK: - Player Stats Widget

struct PlayerStatsProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlayerStatsEntry {
        PlayerStatsEntry(date: Date(), topPerformers: samplePerformers)
    }

    func getSnapshot(in context: Context, completion: @escaping (PlayerStatsEntry) -> Void) {
        if context.isPreview {
            completion(PlayerStatsEntry(date: Date(), topPerformers: samplePerformers)); return
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

                    for leader in leaders {
                        guard let statName = leader["name"] as? String,
                              let leaderList = leader["leaders"] as? [[String: Any]],
                              let topLeader = leaderList.first,
                              let athlete = topLeader["athlete"] as? [String: Any],
                              let displayValue = topLeader["displayValue"] as? String,
                              let value = topLeader["value"] as? Double else { continue }

                        if statName == "rating" { continue }

                        let playerName = athlete["shortName"] as? String ?? "Unknown"

                        performers.append(TopPerformer(
                            playerName: playerName,
                            teamAbbreviation: teamAbbr,
                            teamColor: teamColor,
                            statName: statName,
                            statDisplayName: leader["shortDisplayName"] as? String ?? statName,
                            statValue: displayValue,
                            statNumeric: value,
                            isLive: isLive
                        ))
                    }
                }
            }

            return performers
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

    func top(_ stat: String, count: Int = 5) -> [TopPerformer] {
        Array(topPerformers.filter { $0.statName == stat }.sorted { $0.statNumeric > $1.statNumeric }.prefix(count))
    }

    /// Maximum value for a stat category (for bar graph scaling)
    func maxValue(_ stat: String) -> Double {
        topPerformers.filter { $0.statName == stat }.map { $0.statNumeric }.max() ?? 1
    }
}

// MARK: - Widget Definition

struct PlayerStatsWidget: Widget {
    let kind: String = "PlayerStatsWidget_v4"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlayerStatsProvider()) { entry in
            PlayerStatsWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(white: 0.15)
                }
        }
        .configurationDisplayName("Player Stats")
        .description("Top performers with bar graph leaderboards — points, rebounds, assists, steals, blocks")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

// MARK: - Stat category config

private struct StatCategory {
    let key: String
    let label: String
    let icon: String
    let color: Color
}

private let allStats: [StatCategory] = [
    StatCategory(key: "points", label: "PTS", icon: "flame.fill", color: .orange),
    StatCategory(key: "rebounds", label: "REB", icon: "arrow.up.circle.fill", color: .green),
    StatCategory(key: "assists", label: "AST", icon: "arrow.right.circle.fill", color: .purple),
    StatCategory(key: "steals", label: "STL", icon: "hand.raised.fill", color: .cyan),
    StatCategory(key: "blocks", label: "BLK", icon: "shield.fill", color: .red),
    StatCategory(key: "fieldGoalPct", label: "FG%", icon: "target", color: .blue),
    StatCategory(key: "threePointFieldGoalPct", label: "3P%", icon: "scope", color: .mint),
    StatCategory(key: "freeThrowPct", label: "FT%", icon: "circle.dotted", color: .yellow),
]

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
        case .systemExtraLarge:
            extraLargeView
        default:
            largeView
        }
    }

    // MARK: - Small: Top scorer with big number

    private var smallView: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill").font(.system(size: 9)).foregroundStyle(.orange)
                Text("Top Scorer").font(.system(size: 9, weight: .bold))
                Spacer()
                if entry.hasLive {
                    HStack(spacing: 2) {
                        Circle().fill(.red).frame(width: 4, height: 4)
                        Text("LIVE").font(.system(size: 6, weight: .heavy)).foregroundStyle(.red)
                    }
                }
            }

            if let top = entry.top("points", count: 1).first {
                Spacer(minLength: 0)
                Text(top.statValue)
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(.orange)
                Text("POINTS")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(top.playerName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 3) {
                    teamDot(top.teamColor)
                    Text(top.teamAbbreviation).font(.system(size: 9)).foregroundStyle(.secondary)
                    if top.isLive { Circle().fill(.red).frame(width: 4, height: 4) }
                }
                Spacer(minLength: 0)

                // Mini bar graph of top 3 scorers
                let top3 = entry.top("points", count: 3)
                if top3.count > 1 {
                    HStack(spacing: 2) {
                        ForEach(top3) { p in
                            miniBar(value: p.statNumeric, max: entry.maxValue("points"), color: .orange, label: p.teamAbbreviation)
                        }
                    }
                    .frame(height: 20)
                }
            } else {
                Spacer()
                Text("No games").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(8)
    }

    // MARK: - Medium: 3 stat categories with bar graphs

    private var mediumView: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill").font(.system(size: 10)).foregroundStyle(.blue)
                Text("March Madness Leaders").font(.system(size: 10, weight: .bold))
                Spacer()
                if entry.hasLive {
                    HStack(spacing: 2) {
                        Circle().fill(.red).frame(width: 4, height: 4)
                        Text("LIVE").font(.system(size: 7, weight: .heavy)).foregroundStyle(.red)
                    }
                }
            }

            HStack(spacing: 8) {
                ForEach(allStats.prefix(3), id: \.key) { stat in
                    statBarColumn(stat, count: 3)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(8)
    }

    // MARK: - Large: 5 stat categories with full bar graph leaderboards

    private var largeView: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill").font(.system(size: 10)).foregroundStyle(.blue)
                Text("March Madness Stats").font(.system(size: 11, weight: .bold))
                Spacer()
                if entry.hasLive {
                    HStack(spacing: 2) {
                        Circle().fill(.red).frame(width: 5, height: 5)
                        Text("LIVE").font(.system(size: 8, weight: .heavy)).foregroundStyle(.red)
                    }
                }
            }
            .padding(.bottom, 2)

            ForEach(Array(allStats.prefix(5).enumerated()), id: \.element.key) { idx, stat in
                if idx > 0 { Divider().padding(.horizontal, 4) }
                barGraphSection(stat, count: 3)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
    }

    // MARK: - Extra Large: All 8 stats in 2 columns with full graphs

    private var extraLargeView: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill").font(.system(size: 12)).foregroundStyle(.blue)
                Text("March Madness Player Statistics").font(.system(size: 12, weight: .bold))
                Spacer()
                if entry.hasLive {
                    HStack(spacing: 3) {
                        Circle().fill(.red).frame(width: 5, height: 5)
                        Text("LIVE").font(.system(size: 9, weight: .heavy)).foregroundStyle(.red)
                    }
                }
            }
            .padding(.bottom, 4)

            HStack(alignment: .top, spacing: 12) {
                // Left column
                VStack(spacing: 6) {
                    ForEach(Array(allStats.prefix(4).enumerated()), id: \.element.key) { idx, stat in
                        if idx > 0 { Divider() }
                        barGraphSection(stat, count: 5)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)

                // Right column
                VStack(spacing: 6) {
                    ForEach(Array(allStats.dropFirst(4).prefix(4).enumerated()), id: \.element.key) { idx, stat in
                        if idx > 0 { Divider() }
                        barGraphSection(stat, count: 5)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(8)
    }

    // MARK: - Bar Graph Section (horizontal bars with player names)

    private func barGraphSection(_ stat: StatCategory, count: Int) -> some View {
        let players = entry.top(stat.key, count: count)
        let maxVal = entry.maxValue(stat.key)

        return VStack(spacing: 2) {
            // Header
            HStack(spacing: 3) {
                Image(systemName: stat.icon).font(.system(size: 8)).foregroundStyle(stat.color)
                Text(stat.label).font(.system(size: 8, weight: .heavy)).foregroundStyle(stat.color)
                Spacer()
            }

            if players.isEmpty {
                Text("No data").font(.system(size: 7)).foregroundStyle(.tertiary).padding(.vertical, 2)
            } else {
                ForEach(Array(players.enumerated()), id: \.element.id) { idx, player in
                    barGraphRow(player: player, rank: idx + 1, maxVal: maxVal, color: stat.color)
                }
            }
        }
    }

    private func barGraphRow(player: TopPerformer, rank: Int, maxVal: Double, color: Color) -> some View {
        HStack(spacing: 3) {
            // Rank
            Text("\(rank)")
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 8)

            // Team dot
            teamDot(player.teamColor)

            // Player name + team
            Text(player.playerName)
                .font(.system(size: 8, weight: .medium))
                .lineLimit(1)
                .frame(width: 55, alignment: .leading)

            Text(player.teamAbbreviation)
                .font(.system(size: 7))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)

            // Bar graph
            GeometryReader { geo in
                let barWidth = max(geo.size.width * CGFloat(player.statNumeric / max(maxVal, 1)), 4)
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.1))
                        .frame(height: 10)

                    // Filled bar
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.6), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: barWidth, height: 10)
                }
            }
            .frame(height: 10)

            // Live indicator
            if player.isLive {
                Circle().fill(.red).frame(width: 3, height: 3)
            }

            // Value
            Text(player.statValue)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 22, alignment: .trailing)
        }
        .frame(height: 12)
    }

    // MARK: - Medium: stat column with vertical bars

    private func statBarColumn(_ stat: StatCategory, count: Int) -> some View {
        let players = entry.top(stat.key, count: count)
        let maxVal = entry.maxValue(stat.key)

        return VStack(spacing: 2) {
            // Header
            HStack(spacing: 2) {
                Image(systemName: stat.icon).font(.system(size: 8)).foregroundStyle(stat.color)
                Text(stat.label).font(.system(size: 8, weight: .heavy)).foregroundStyle(stat.color)
            }

            // Vertical bar chart
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(players) { player in
                    VStack(spacing: 1) {
                        // Value on top
                        Text(player.statValue)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(stat.color)

                        // Vertical bar
                        GeometryReader { geo in
                            let barH = max(geo.size.height * CGFloat(player.statNumeric / max(maxVal, 1)), 4)
                            VStack {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(
                                        LinearGradient(
                                            colors: [stat.color.opacity(0.4), stat.color],
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                    )
                                    .frame(height: barH)
                            }
                        }

                        // Player name
                        Text(player.playerName.components(separatedBy: " ").last ?? player.playerName)
                            .font(.system(size: 6, weight: .medium))
                            .lineLimit(1)

                        teamDot(player.teamColor)

                        if player.isLive {
                            Circle().fill(.red).frame(width: 3, height: 3)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Mini bar (for small widget)

    private func miniBar(value: Double, max maxVal: Double, color: Color, label: String) -> some View {
        VStack(spacing: 1) {
            Text("\(Int(value))")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(color)

            GeometryReader { geo in
                let h = max(geo.size.height * CGFloat(value / max(maxVal, 1)), 2)
                VStack {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color.opacity(0.7))
                        .frame(height: h)
                }
            }

            Text(label)
                .font(.system(size: 5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func teamDot(_ hex: String?) -> some View {
        Circle().fill(Color(hex: hex) ?? .gray).frame(width: 5, height: 5)
    }
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
    // Points
    TopPerformer(playerName: "C. Cooper", teamAbbreviation: "MSU", teamColor: "18453B",
                 statName: "points", statDisplayName: "Pts", statValue: "28", statNumeric: 28, isLive: true),
    TopPerformer(playerName: "N. Boyd", teamAbbreviation: "WIS", teamColor: "C5050C",
                 statName: "points", statDisplayName: "Pts", statValue: "27", statNumeric: 27, isLive: false),
    TopPerformer(playerName: "R. Martin", teamAbbreviation: "HPU", teamColor: "330072",
                 statName: "points", statDisplayName: "Pts", statValue: "23", statNumeric: 23, isLive: false),
    TopPerformer(playerName: "J. Flagg", teamAbbreviation: "DUKE", teamColor: "003087",
                 statName: "points", statDisplayName: "Pts", statValue: "21", statNumeric: 21, isLive: false),
    TopPerformer(playerName: "D. Knecht", teamAbbreviation: "TENN", teamColor: "FF8200",
                 statName: "points", statDisplayName: "Pts", statValue: "19", statNumeric: 19, isLive: false),
    // Rebounds
    TopPerformer(playerName: "T. Anderson", teamAbbreviation: "HPU", teamColor: "330072",
                 statName: "rebounds", statDisplayName: "Reb", statValue: "14", statNumeric: 14, isLive: false),
    TopPerformer(playerName: "K. Ware", teamAbbreviation: "HOU", teamColor: "C8102E",
                 statName: "rebounds", statDisplayName: "Reb", statValue: "12", statNumeric: 12, isLive: false),
    TopPerformer(playerName: "A. Reeves", teamAbbreviation: "UK", teamColor: "0033A0",
                 statName: "rebounds", statDisplayName: "Reb", statValue: "11", statNumeric: 11, isLive: false),
    TopPerformer(playerName: "M. Miles", teamAbbreviation: "MSU", teamColor: "18453B",
                 statName: "rebounds", statDisplayName: "Reb", statValue: "9", statNumeric: 9, isLive: true),
    // Assists
    TopPerformer(playerName: "J. Fears", teamAbbreviation: "MSU", teamColor: "18453B",
                 statName: "assists", statDisplayName: "Ast", statValue: "11", statNumeric: 11, isLive: true),
    TopPerformer(playerName: "R. Martin", teamAbbreviation: "HPU", teamColor: "330072",
                 statName: "assists", statDisplayName: "Ast", statValue: "10", statNumeric: 10, isLive: false),
    TopPerformer(playerName: "M. Sears", teamAbbreviation: "KU", teamColor: "0051BA",
                 statName: "assists", statDisplayName: "Ast", statValue: "8", statNumeric: 8, isLive: false),
    // Steals
    TopPerformer(playerName: "T. Battle", teamAbbreviation: "ARK", teamColor: "9D2235",
                 statName: "steals", statDisplayName: "Stl", statValue: "5", statNumeric: 5, isLive: false),
    TopPerformer(playerName: "J. Fears", teamAbbreviation: "MSU", teamColor: "18453B",
                 statName: "steals", statDisplayName: "Stl", statValue: "4", statNumeric: 4, isLive: true),
    TopPerformer(playerName: "N. Boyd", teamAbbreviation: "WIS", teamColor: "C5050C",
                 statName: "steals", statDisplayName: "Stl", statValue: "3", statNumeric: 3, isLive: false),
    // Blocks
    TopPerformer(playerName: "K. Ware", teamAbbreviation: "HOU", teamColor: "C8102E",
                 statName: "blocks", statDisplayName: "Blk", statValue: "6", statNumeric: 6, isLive: false),
    TopPerformer(playerName: "C. Cooper", teamAbbreviation: "MSU", teamColor: "18453B",
                 statName: "blocks", statDisplayName: "Blk", statValue: "3", statNumeric: 3, isLive: true),
]
