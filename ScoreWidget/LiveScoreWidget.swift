import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct LiveScoreProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScoreEntry {
        ScoreEntry(date: Date(), games: sampleGames, logoCache: [:])
    }

    func getSnapshot(in context: Context, completion: @escaping (ScoreEntry) -> Void) {
        if context.isPreview {
            completion(ScoreEntry(date: Date(), games: sampleGames, logoCache: [:])); return
        }
        Task {
            let games = await fetchLiveScores()
            let logos = await downloadLogos(for: games)
            completion(ScoreEntry(date: Date(), games: games, logoCache: logos))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScoreEntry>) -> Void) {
        Task {
            let games = await fetchLiveScores()
            let finalGames = games.isEmpty ? sampleGames : games
            let logos = await downloadLogos(for: finalGames)
            let entry = ScoreEntry(date: Date(), games: finalGames, logoCache: logos)
            let hasLive = games.contains { $0.isLive }
            let refreshDate = Calendar.current.date(byAdding: .minute, value: hasLive ? 1 : 5, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(refreshDate)))
        }
    }

    /// Download all team logos and return as [url_string: Data]
    private func downloadLogos(for games: [SharedGame]) async -> [String: Data] {
        var cache: [String: Data] = [:]
        var urls: Set<String> = []

        for game in games {
            if let u = game.awayLogo { urls.insert(u) }
            if let u = game.homeLogo { urls.insert(u) }
        }

        await withTaskGroup(of: (String, Data?).self) { group in
            for urlString in urls {
                group.addTask {
                    guard let url = URL(string: urlString) else { return (urlString, nil) }
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        return (urlString, data)
                    } catch {
                        return (urlString, nil)
                    }
                }
            }
            for await (urlString, data) in group {
                if let data = data {
                    cache[urlString] = data
                }
            }
        }

        return cache
    }

    private func fetchLiveScores() async -> [SharedGame] {
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/scoreboard?groups=100&limit=100") else {
            return sampleGames
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(WidgetScoreboardResponse.self, from: data)
            return response.events.map { event in
                let away = event.competitions.first?.competitors.first { $0.homeAway == "away" }
                let home = event.competitions.first?.competitors.first { $0.homeAway == "home" }
                let headline = event.notes?.first?.headline
                    ?? event.competitions.first?.notes?.first?.headline
                let parts = headline?.components(separatedBy: " - ") ?? []
                var regionStr: String? = nil
                if parts.count >= 2 {
                    let r = parts[parts.count - 2].trimmingCharacters(in: .whitespaces)
                    regionStr = r.replacingOccurrences(of: " Region", with: "")
                }

                return SharedGame(
                    id: event.id,
                    awayTeam: away?.team.displayName ?? "TBD",
                    awayAbbreviation: away?.team.abbreviation ?? "TBD",
                    awayScore: away?.score ?? "0",
                    awaySeed: away?.curatedRank?.current,
                    awayLogo: away?.team.logo,
                    awayColor: away?.team.color,
                    homeTeam: home?.team.displayName ?? "TBD",
                    homeAbbreviation: home?.team.abbreviation ?? "TBD",
                    homeScore: home?.score ?? "0",
                    homeSeed: home?.curatedRank?.current,
                    homeLogo: home?.team.logo,
                    homeColor: home?.team.color,
                    state: event.status.type.state,
                    detail: event.status.type.detail,
                    shortDetail: event.status.type.shortDetail,
                    period: event.status.period,
                    displayClock: event.status.displayClock,
                    startDate: ISO8601DateFormatter().date(from: event.date),
                    roundName: parts.last?.trimmingCharacters(in: .whitespaces),
                    regionName: regionStr,
                    broadcast: event.competitions.first?.broadcasts?.first?.names?.first,
                    isUpset: {
                        guard event.status.type.state != "pre",
                              let away, let home,
                              let aSeed = away.curatedRank?.current,
                              let hSeed = home.curatedRank?.current,
                              let aScore = Int(away.score ?? "0"),
                              let hScore = Int(home.score ?? "0") else { return false }
                        return (aSeed > hSeed && aScore > hScore) || (hSeed > aSeed && hScore > aScore)
                    }()
                )
            }
        } catch {
            return sampleGames
        }
    }
}

// MARK: - Minimal Codable types for widget-side ESPN parsing

private struct WidgetScoreboardResponse: Codable {
    let events: [WidgetEvent]
}

private struct WidgetEvent: Codable {
    let id: String
    let date: String
    let competitions: [WidgetCompetition]
    let status: WidgetStatus
    let notes: [WidgetNote]?
}

private struct WidgetCompetition: Codable {
    let competitors: [WidgetCompetitor]
    let broadcasts: [WidgetBroadcast]?
    let notes: [WidgetNote]?
}

private struct WidgetCompetitor: Codable {
    let homeAway: String
    let team: WidgetTeam
    let score: String?
    let curatedRank: WidgetRank?
}

private struct WidgetTeam: Codable {
    let id: String
    let abbreviation: String
    let displayName: String
    let color: String?
    let logo: String?
}

private struct WidgetRank: Codable {
    let current: Int?
}

private struct WidgetStatus: Codable {
    let displayClock: String?
    let period: Int
    let type: WidgetStatusType
}

private struct WidgetStatusType: Codable {
    let state: String
    let detail: String?
    let shortDetail: String?
}

private struct WidgetNote: Codable {
    let headline: String?
}

private struct WidgetBroadcast: Codable {
    let names: [String]?
}

// MARK: - Timeline Entry

struct ScoreEntry: TimelineEntry {
    let date: Date
    let games: [SharedGame]
    let logoCache: [String: Data]  // url -> image data

    var liveGames: [SharedGame] { games.filter { $0.isLive } }
    var recentGames: [SharedGame] {
        let live = liveGames
        if !live.isEmpty { return live }
        let finals = games.filter { $0.isFinal }
        if !finals.isEmpty { return Array(finals.prefix(4)) }
        return Array(games.prefix(4))
    }

    func logoImage(for urlString: String?) -> NSImage? {
        guard let urlString, let data = logoCache[urlString] else { return nil }
        return NSImage(data: data)
    }
}

// MARK: - Widget Definition

struct LiveScoreWidget: Widget {
    let kind: String = "LiveScoreWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LiveScoreProvider()) { entry in
            LiveScoreWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("March Madness Scores")
        .description("Live NCAA Tournament scores with team logos")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Widget Views

struct LiveScoreWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: ScoreEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallWidget
        case .systemMedium:
            mediumWidget
        case .systemLarge:
            largeWidget
        default:
            mediumWidget
        }
    }

    // MARK: - Small Widget (single game)

    private var smallWidget: some View {
        VStack(spacing: 6) {
            if let game = entry.recentGames.first {
                HStack {
                    if game.isLive {
                        HStack(spacing: 3) {
                            Circle().fill(.red).frame(width: 5, height: 5)
                            Text("LIVE").font(.system(size: 8, weight: .heavy)).foregroundStyle(.red)
                        }
                    }
                    Spacer()
                    if let round = game.roundName {
                        Text(round).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }

                Spacer()

                HStack(spacing: 0) {
                    // Away
                    VStack(spacing: 3) {
                        teamLogo(game.awayLogo, color: game.awayColor, size: 28)
                        HStack(spacing: 2) {
                            if let seed = game.awaySeed {
                                Text("\(seed)").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                            }
                            Text(game.awayAbbreviation).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Score
                    VStack(spacing: 2) {
                        if game.isLive || game.isFinal {
                            HStack(spacing: 4) {
                                Text(game.awayScore).font(.system(size: 22, weight: .bold, design: .rounded))
                                Text("-").font(.system(size: 14)).foregroundStyle(.secondary)
                                Text(game.homeScore).font(.system(size: 22, weight: .bold, design: .rounded))
                            }
                        }
                        if game.isLive {
                            Text(game.shortDetail ?? "Live").font(.system(size: 9, weight: .bold)).foregroundStyle(.red)
                        } else if game.isFinal {
                            Text("Final").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                        } else {
                            Text(game.detail ?? "Upcoming").font(.system(size: 11, weight: .semibold))
                        }
                    }

                    // Home
                    VStack(spacing: 3) {
                        teamLogo(game.homeLogo, color: game.homeColor, size: 28)
                        HStack(spacing: 2) {
                            Text(game.homeAbbreviation).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            if let seed = game.homeSeed {
                                Text("\(seed)").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                Spacer()

                if game.isUpset {
                    HStack(spacing: 2) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 7))
                        Text("UPSET").font(.system(size: 7, weight: .heavy))
                    }
                    .foregroundStyle(.orange)
                }
            } else {
                emptyState
            }
        }
        .padding(4)
    }

    // MARK: - Medium Widget

    private var mediumWidget: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "basketball.fill").font(.system(size: 10)).foregroundStyle(.orange)
                Text("March Madness").font(.system(size: 11, weight: .bold))
                Spacer()
                if entry.liveGames.count > 0 {
                    HStack(spacing: 3) {
                        Circle().fill(.red).frame(width: 5, height: 5)
                        Text("\(entry.liveGames.count) LIVE").font(.system(size: 8, weight: .heavy)).foregroundStyle(.red)
                    }
                }
            }

            if entry.recentGames.isEmpty {
                Spacer(); emptyState; Spacer()
            } else {
                ForEach(Array(entry.recentGames.prefix(3))) { game in
                    compactGameRow(game)
                    if game.id != entry.recentGames.prefix(3).last?.id { Divider() }
                }
            }
        }
        .padding(4)
    }

    // MARK: - Large Widget

    private var largeWidget: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "basketball.fill").font(.system(size: 12)).foregroundStyle(.orange)
                Text("March Madness").font(.system(size: 13, weight: .bold))
                Spacer()
                if entry.liveGames.count > 0 {
                    HStack(spacing: 3) {
                        Circle().fill(.red).frame(width: 6, height: 6)
                        Text("\(entry.liveGames.count) LIVE").font(.system(size: 9, weight: .heavy)).foregroundStyle(.red)
                    }
                }
            }
            .padding(.bottom, 2)

            if entry.recentGames.isEmpty {
                Spacer(); emptyState; Spacer()
            } else {
                ForEach(Array(entry.recentGames.prefix(6))) { game in
                    expandedGameRow(game)
                    if game.id != entry.recentGames.prefix(6).last?.id { Divider() }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(4)
    }

    // MARK: - Row Components

    private func compactGameRow(_ game: SharedGame) -> some View {
        HStack(spacing: 6) {
            if game.isLive { Circle().fill(.red).frame(width: 4, height: 4) }

            teamLogo(game.awayLogo, color: game.awayColor, size: 16)
            if let seed = game.awaySeed {
                Text("\(seed)").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
            }
            Text(game.awayAbbreviation).font(.system(size: 12, weight: .semibold)).lineLimit(1).frame(width: 36, alignment: .leading)

            Spacer()

            if game.isLive || game.isFinal {
                Text("\(game.awayScore) - \(game.homeScore)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(game.isLive ? .red : .primary)
            } else {
                Text(game.shortDetail ?? "—").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }

            Spacer()

            Text(game.homeAbbreviation).font(.system(size: 12, weight: .semibold)).lineLimit(1).frame(width: 36, alignment: .trailing)
            if let seed = game.homeSeed {
                Text("\(seed)").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
            }
            teamLogo(game.homeLogo, color: game.homeColor, size: 16)

            if game.isUpset {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 8)).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private func expandedGameRow(_ game: SharedGame) -> some View {
        HStack(spacing: 8) {
            if game.isLive { Circle().fill(.red).frame(width: 5, height: 5) }

            teamLogo(game.awayLogo, color: game.awayColor, size: 20)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 3) {
                    if let seed = game.awaySeed {
                        Text("(\(seed))").font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                    Text(game.awayAbbreviation).font(.system(size: 12, weight: .semibold))
                }
            }

            Spacer()

            VStack(spacing: 1) {
                if game.isLive || game.isFinal {
                    Text("\(game.awayScore) - \(game.homeScore)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(game.isLive ? .red : .primary)
                }
                if game.isLive {
                    Text(game.shortDetail ?? "Live").font(.system(size: 8, weight: .bold)).foregroundStyle(.red)
                } else if game.isFinal {
                    Text("Final").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                } else {
                    Text(game.shortDetail ?? "—").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 70)

            Spacer()

            VStack(alignment: .trailing, spacing: 0) {
                HStack(spacing: 3) {
                    Text(game.homeAbbreviation).font(.system(size: 12, weight: .semibold))
                    if let seed = game.homeSeed {
                        Text("(\(seed))").font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                }
            }
            teamLogo(game.homeLogo, color: game.homeColor, size: 20)

            if game.isUpset {
                HStack(spacing: 2) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 7))
                    Text("!").font(.system(size: 7, weight: .heavy))
                }
                .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Team Logo (uses pre-downloaded image data)

    private func teamLogo(_ urlString: String?, color: String?, size: CGFloat) -> some View {
        ZStack {
            if let hex = color {
                Circle()
                    .fill(Color(hex: hex)?.opacity(0.15) ?? Color.gray.opacity(0.15))
                    .frame(width: size + 4, height: size + 4)
            }
            if let nsImage = entry.logoImage(for: urlString) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "basketball.fill")
                    .font(.system(size: size * 0.6))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "basketball").font(.title3).foregroundStyle(.secondary)
            Text("No games right now").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Color hex extension for widget

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

let sampleGames: [SharedGame] = [
    SharedGame(
        id: "sample1", awayTeam: "Duke", awayAbbreviation: "DUKE", awayScore: "72",
        awaySeed: 4, awayLogo: nil, awayColor: "003087",
        homeTeam: "UNC", homeAbbreviation: "UNC", homeScore: "68",
        homeSeed: 1, homeLogo: nil, homeColor: "7BAFD4",
        state: "in", detail: "2nd Half - 4:32", shortDetail: "2nd 4:32",
        period: 2, displayClock: "4:32", startDate: Date(),
        roundName: "Sweet 16", regionName: "East", broadcast: "CBS",
        isUpset: true
    ),
    SharedGame(
        id: "sample2", awayTeam: "Kansas", awayAbbreviation: "KU", awayScore: "65",
        awaySeed: 1, awayLogo: nil, awayColor: "0051BA",
        homeTeam: "Kentucky", homeAbbreviation: "UK", homeScore: "58",
        homeSeed: 3, homeLogo: nil, homeColor: "0033A0",
        state: "post", detail: "Final", shortDetail: "Final",
        period: 2, displayClock: "0:00", startDate: Date().addingTimeInterval(-3600),
        roundName: "2nd Round", regionName: "South", broadcast: "TNT",
        isUpset: false
    ),
]
