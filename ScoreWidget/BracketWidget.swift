import WidgetKit
import SwiftUI

// MARK: - Bracket Widget Provider

struct BracketProvider: TimelineProvider {
    func placeholder(in context: Context) -> BracketEntry {
        BracketEntry(date: Date(), games: sampleBracketGames)
    }

    func getSnapshot(in context: Context, completion: @escaping (BracketEntry) -> Void) {
        if context.isPreview {
            completion(BracketEntry(date: Date(), games: sampleBracketGames))
            return
        }
        Task {
            let games = await fetchScores()
            completion(BracketEntry(date: Date(), games: games.isEmpty ? sampleBracketGames : games))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BracketEntry>) -> Void) {
        Task {
            let games = await fetchScores()
            let entry = BracketEntry(date: Date(), games: games.isEmpty ? sampleBracketGames : games)
            let hasLive = games.contains { $0.isLive }
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: hasLive ? 1 : 10, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private func fetchScores() async -> [SharedGame] {
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/scoreboard?groups=100&limit=100") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let events = json?["events"] as? [[String: Any]] else { return [] }
            return events.compactMap { parseEvent($0) }
        } catch { return [] }
    }

    private func parseEvent(_ event: [String: Any]) -> SharedGame? {
        guard let id = event["id"] as? String,
              let competitions = event["competitions"] as? [[String: Any]],
              let comp = competitions.first,
              let competitors = comp["competitors"] as? [[String: Any]],
              let status = event["status"] as? [String: Any],
              let statusType = status["type"] as? [String: Any],
              let state = statusType["state"] as? String else { return nil }

        let away = competitors.first { ($0["homeAway"] as? String) == "away" }
        let home = competitors.first { ($0["homeAway"] as? String) == "home" }
        let awayTeam = away?["team"] as? [String: Any]
        let homeTeam = home?["team"] as? [String: Any]
        let awayRank = away?["curatedRank"] as? [String: Any]
        let homeRank = home?["curatedRank"] as? [String: Any]
        let eventNotes = event["notes"] as? [[String: Any]]
        let compNotes = comp["notes"] as? [[String: Any]]
        let headline = eventNotes?.first?["headline"] as? String ?? compNotes?.first?["headline"] as? String
        let parts = headline?.components(separatedBy: " - ") ?? []
        var regionStr: String? = nil
        if parts.count >= 2 {
            regionStr = parts[parts.count - 2].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " Region", with: "")
        }

        return SharedGame(
            id: id,
            awayTeam: awayTeam?["displayName"] as? String ?? "TBD",
            awayAbbreviation: awayTeam?["abbreviation"] as? String ?? "TBD",
            awayScore: away?["score"] as? String ?? "0",
            awaySeed: awayRank?["current"] as? Int,
            awayLogo: awayTeam?["logo"] as? String,
            awayColor: awayTeam?["color"] as? String,
            homeTeam: homeTeam?["displayName"] as? String ?? "TBD",
            homeAbbreviation: homeTeam?["abbreviation"] as? String ?? "TBD",
            homeScore: home?["score"] as? String ?? "0",
            homeSeed: homeRank?["current"] as? Int,
            homeLogo: homeTeam?["logo"] as? String,
            homeColor: homeTeam?["color"] as? String,
            state: state,
            detail: statusType["detail"] as? String,
            shortDetail: statusType["shortDetail"] as? String,
            period: status["period"] as? Int ?? 0,
            displayClock: status["displayClock"] as? String,
            startDate: nil,
            roundName: parts.last?.trimmingCharacters(in: .whitespaces),
            regionName: regionStr,
            broadcast: nil,
            isUpset: false
        )
    }
}

// MARK: - Entry

struct BracketEntry: TimelineEntry {
    let date: Date
    let games: [SharedGame]
    var liveGames: [SharedGame] { games.filter { $0.isLive } }

    var regions: [String] {
        var seen = Set<String>()
        return games.compactMap { $0.regionName }.filter { seen.insert($0).inserted }
    }

    /// Get games for a region organized by round order
    func roundsFor(region: String) -> [[SharedGame]] {
        let roundOrder = ["1st Round", "2nd Round", "Sweet 16", "Elite 8"]
        let regionGames = games.filter { $0.regionName == region }
        return roundOrder.map { round in
            regionGames.filter { $0.roundName == round }
        }.filter { !$0.isEmpty }
    }
}

// MARK: - Widget Definition

struct BracketWidget: Widget {
    let kind: String = "BracketWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BracketProvider()) { entry in
            BracketWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tournament Bracket")
        .description("Visual bracket tree with matchup lines and live scores")
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
    }
}

// MARK: - Main View

struct BracketWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: BracketEntry

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.yellow)
                Text("NCAA Tournament")
                    .font(.system(size: 10, weight: .bold))
                Spacer()
                if !entry.liveGames.isEmpty {
                    HStack(spacing: 2) {
                        Circle().fill(.red).frame(width: 4, height: 4)
                        Text("\(entry.liveGames.count) LIVE")
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.bottom, 4)

            // Bracket content
            switch family {
            case .systemMedium:
                // One region bracket
                if let region = entry.regions.first {
                    regionBracketTree(region: region)
                }
            case .systemLarge:
                // Two region brackets stacked
                if entry.regions.count >= 2 {
                    regionBracketTree(region: entry.regions[0])
                    Spacer(minLength: 4)
                    Divider().padding(.horizontal, 4)
                    Spacer(minLength: 4)
                    regionBracketTree(region: entry.regions[1])
                } else if let region = entry.regions.first {
                    regionBracketTree(region: region)
                }
            case .systemExtraLarge:
                // All 4 regions in 2x2 grid
                if entry.regions.count >= 4 {
                    HStack(spacing: 8) {
                        VStack(spacing: 6) {
                            regionBracketTree(region: entry.regions[0])
                            Divider()
                            regionBracketTree(region: entry.regions[2])
                        }
                        VStack(spacing: 6) {
                            regionBracketTree(region: entry.regions[1])
                            Divider()
                            regionBracketTree(region: entry.regions[3])
                        }
                    }
                } else {
                    ForEach(entry.regions, id: \.self) { region in
                        regionBracketTree(region: region)
                    }
                }
            default:
                if let region = entry.regions.first {
                    regionBracketTree(region: region)
                }
            }
        }
        .padding(6)
    }

    // MARK: - Region Bracket Tree
    // This creates the actual bracket visual: matchups in columns with connector lines

    private func regionBracketTree(region: String) -> some View {
        let rounds = entry.roundsFor(region: region)

        return VStack(spacing: 0) {
            // Region label
            Text(region.uppercased())
                .font(.system(size: 7, weight: .heavy))
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 2)

            if rounds.isEmpty {
                Text("No games yet")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // The bracket tree: each round is a column, reading left to right
                HStack(alignment: .center, spacing: 0) {
                    ForEach(Array(rounds.enumerated()), id: \.offset) { roundIdx, roundGames in
                        // Round column
                        bracketRoundColumn(
                            games: roundGames,
                            roundIndex: roundIdx,
                            totalRounds: rounds.count
                        )

                        // Connector lines between rounds
                        if roundIdx < rounds.count - 1 {
                            bracketConnectors(
                                fromCount: roundGames.count,
                                roundIndex: roundIdx
                            )
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Round Column: matchup boxes stacked with bracket spacing

    private func bracketRoundColumn(games: [SharedGame], roundIndex: Int, totalRounds: Int) -> some View {
        // Spacing increases each round to create the bracket tree effect
        let spacing: CGFloat = roundIndex == 0 ? 4 : (CGFloat(roundIndex) * 20 + 4)

        return VStack(spacing: spacing) {
            ForEach(games) { game in
                matchupBox(game)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Bracket Connector Lines (pure SwiftUI, no Canvas)

    private func bracketConnectors(fromCount: Int, roundIndex: Int) -> some View {
        let pairCount = fromCount / 2

        return VStack(spacing: CGFloat(roundIndex) * 20 + 4) {
            ForEach(0..<max(pairCount, 1), id: \.self) { _ in
                // Each connector: ┐
                //                  ├──
                //                 ┘
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        // Top horizontal
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.25))
                                .frame(width: 6, height: 0.5)
                            Spacer(minLength: 0)
                        }
                        // Vertical bar
                        Rectangle()
                            .fill(Color.secondary.opacity(0.25))
                            .frame(width: 0.5)
                        // Bottom horizontal
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.25))
                                .frame(width: 6, height: 0.5)
                            Spacer(minLength: 0)
                        }
                    }
                    // Outgoing horizontal to next round
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 6, height: 0.5)
                }
                .frame(width: 12)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Matchup Box: two teams in a compact bracket cell

    private func matchupBox(_ game: SharedGame) -> some View {
        VStack(spacing: 0) {
            teamLine(seed: game.awaySeed, abbr: game.awayAbbreviation, score: game.awayScore,
                     winning: awayLeads(game), live: game.isLive, final: game.isFinal)

            Rectangle()
                .fill(game.isLive ? Color.red.opacity(0.5) : Color.secondary.opacity(0.15))
                .frame(height: 0.5)

            teamLine(seed: game.homeSeed, abbr: game.homeAbbreviation, score: game.homeScore,
                     winning: homeLeads(game), live: game.isLive, final: game.isFinal)
        }
        .frame(minWidth: 60)
        .background(
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(game.isLive ? Color.red.opacity(0.6) : Color.secondary.opacity(0.12), lineWidth: game.isLive ? 1 : 0.5)
        )
    }

    private func teamLine(seed: Int?, abbr: String, score: String, winning: Bool, live: Bool, final isFinal: Bool) -> some View {
        HStack(spacing: 2) {
            if let seed = seed {
                Text("\(seed)")
                    .font(.system(size: 6, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 9, alignment: .trailing)
            }
            Text(abbr)
                .font(.system(size: 7, weight: winning ? .bold : .regular))
                .lineLimit(1)
            Spacer(minLength: 0)
            if live || isFinal {
                Text(score)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(live ? .red : (winning ? .primary : .secondary))
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        .background(winning && isFinal ? Color.green.opacity(0.06) : Color.clear)
    }

    private func awayLeads(_ g: SharedGame) -> Bool {
        guard let a = g.awayScoreInt, let h = g.homeScoreInt else { return false }; return a > h
    }
    private func homeLeads(_ g: SharedGame) -> Bool {
        guard let a = g.awayScoreInt, let h = g.homeScoreInt else { return false }; return h > a
    }
}

// MARK: - Sample data

private let sampleBracketGames: [SharedGame] = [
    SharedGame(id: "s1", awayTeam: "Duke", awayAbbreviation: "DUKE", awayScore: "71", awaySeed: 1, awayLogo: nil, awayColor: "003087", homeTeam: "Siena", homeAbbreviation: "SIE", homeScore: "65", homeSeed: 16, homeLogo: nil, homeColor: nil, state: "post", detail: "Final", shortDetail: "Final", period: 2, displayClock: "0:00", startDate: nil, roundName: "1st Round", regionName: "East", broadcast: nil, isUpset: false),
    SharedGame(id: "s2", awayTeam: "MSU", awayAbbreviation: "MSU", awayScore: "92", awaySeed: 3, awayLogo: nil, awayColor: "18453B", homeTeam: "NDSU", homeAbbreviation: "NDSU", homeScore: "67", homeSeed: 14, homeLogo: nil, homeColor: nil, state: "post", detail: "Final", shortDetail: "Final", period: 2, displayClock: "0:00", startDate: nil, roundName: "1st Round", regionName: "East", broadcast: nil, isUpset: false),
    SharedGame(id: "s3", awayTeam: "Louisville", awayAbbreviation: "LOU", awayScore: "83", awaySeed: 6, awayLogo: nil, awayColor: "AD0000", homeTeam: "USF", homeAbbreviation: "USF", homeScore: "79", homeSeed: 11, homeLogo: nil, homeColor: nil, state: "post", detail: "Final", shortDetail: "Final", period: 2, displayClock: "0:00", startDate: nil, roundName: "1st Round", regionName: "East", broadcast: nil, isUpset: false),
    SharedGame(id: "s4", awayTeam: "TCU", awayAbbreviation: "TCU", awayScore: "66", awaySeed: 9, awayLogo: nil, awayColor: "4D1979", homeTeam: "Ohio St", homeAbbreviation: "OSU", homeScore: "64", homeSeed: 8, homeLogo: nil, homeColor: nil, state: "post", detail: "Final", shortDetail: "Final", period: 2, displayClock: "0:00", startDate: nil, roundName: "1st Round", regionName: "East", broadcast: nil, isUpset: true),
    SharedGame(id: "s5", awayTeam: "Texas", awayAbbreviation: "TEX", awayScore: "79", awaySeed: 11, awayLogo: nil, awayColor: "BF5700", homeTeam: "BYU", homeAbbreviation: "BYU", homeScore: "71", homeSeed: 6, homeLogo: nil, homeColor: nil, state: "post", detail: "Final", shortDetail: "Final", period: 2, displayClock: "0:00", startDate: nil, roundName: "1st Round", regionName: "West", broadcast: nil, isUpset: true),
    SharedGame(id: "s6", awayTeam: "Arkansas", awayAbbreviation: "ARK", awayScore: "97", awaySeed: 4, awayLogo: nil, awayColor: "9D2235", homeTeam: "Hawaii", homeAbbreviation: "HAW", homeScore: "78", homeSeed: 13, homeLogo: nil, homeColor: nil, state: "post", detail: "Final", shortDetail: "Final", period: 2, displayClock: "0:00", startDate: nil, roundName: "1st Round", regionName: "West", broadcast: nil, isUpset: false),
    SharedGame(id: "s7", awayTeam: "Gonzaga", awayAbbreviation: "GONZ", awayScore: "0", awaySeed: 3, awayLogo: nil, awayColor: "002967", homeTeam: "Kennesaw", homeAbbreviation: "KENN", homeScore: "0", homeSeed: 14, homeLogo: nil, homeColor: nil, state: "pre", detail: "7:10 PM", shortDetail: "7:10 PM", period: 0, displayClock: nil, startDate: nil, roundName: "1st Round", regionName: "West", broadcast: nil, isUpset: false),
    SharedGame(id: "s8", awayTeam: "HPU", awayAbbreviation: "HPU", awayScore: "83", awaySeed: 12, awayLogo: nil, awayColor: "330072", homeTeam: "Wisconsin", homeAbbreviation: "WIS", homeScore: "82", homeSeed: 5, homeLogo: nil, homeColor: nil, state: "post", detail: "Final", shortDetail: "Final", period: 2, displayClock: "0:00", startDate: nil, roundName: "1st Round", regionName: "West", broadcast: nil, isUpset: true),
]
