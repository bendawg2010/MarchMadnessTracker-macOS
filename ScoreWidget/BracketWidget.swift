import WidgetKit
import SwiftUI

// MARK: - Provider

struct BracketProvider: TimelineProvider {
    func placeholder(in context: Context) -> BracketEntry {
        BracketEntry(date: Date(), games: sampleBracketGames)
    }
    func getSnapshot(in context: Context, completion: @escaping (BracketEntry) -> Void) {
        if context.isPreview {
            completion(BracketEntry(date: Date(), games: sampleBracketGames)); return
        }
        Task {
            let g = await fetchScores()
            completion(BracketEntry(date: Date(), games: g.isEmpty ? sampleBracketGames : g))
        }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BracketEntry>) -> Void) {
        Task {
            let g = await fetchScores()
            let entry = BracketEntry(date: Date(), games: g.isEmpty ? sampleBracketGames : g)
            let next = Calendar.current.date(byAdding: .minute, value: g.contains { $0.isLive } ? 1 : 10, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(next)))
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
              let comps = event["competitions"] as? [[String: Any]], let comp = comps.first,
              let competitors = comp["competitors"] as? [[String: Any]],
              let status = event["status"] as? [String: Any],
              let sType = status["type"] as? [String: Any],
              let state = sType["state"] as? String else { return nil }
        let away = competitors.first { ($0["homeAway"] as? String) == "away" }
        let home = competitors.first { ($0["homeAway"] as? String) == "home" }
        let aT = away?["team"] as? [String: Any]; let hT = home?["team"] as? [String: Any]
        let aR = away?["curatedRank"] as? [String: Any]; let hR = home?["curatedRank"] as? [String: Any]
        let headline = (event["notes"] as? [[String: Any]])?.first?["headline"] as? String
            ?? (comp["notes"] as? [[String: Any]])?.first?["headline"] as? String
        let parts = headline?.components(separatedBy: " - ") ?? []
        var region: String? = nil
        if parts.count >= 2 { region = parts[parts.count - 2].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " Region", with: "") }
        return SharedGame(id: id, awayTeam: aT?["displayName"] as? String ?? "TBD", awayAbbreviation: aT?["abbreviation"] as? String ?? "TBD", awayScore: away?["score"] as? String ?? "0", awaySeed: aR?["current"] as? Int, awayLogo: aT?["logo"] as? String, awayColor: aT?["color"] as? String, homeTeam: hT?["displayName"] as? String ?? "TBD", homeAbbreviation: hT?["abbreviation"] as? String ?? "TBD", homeScore: home?["score"] as? String ?? "0", homeSeed: hR?["current"] as? Int, homeLogo: hT?["logo"] as? String, homeColor: hT?["color"] as? String, state: state, detail: sType["detail"] as? String, shortDetail: sType["shortDetail"] as? String, period: status["period"] as? Int ?? 0, displayClock: status["displayClock"] as? String, startDate: nil, roundName: parts.last?.trimmingCharacters(in: .whitespaces), regionName: region, broadcast: nil, isUpset: false)
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
    func roundsFor(region: String) -> [[SharedGame]] {
        let order = ["1st Round", "2nd Round", "Sweet 16", "Elite 8"]
        let rg = games.filter { $0.regionName == region }
        return order.map { r in rg.filter { $0.roundName == r } }.filter { !$0.isEmpty }
    }
    var finalFourGames: [SharedGame] {
        games.filter { $0.roundName == "Final Four" || $0.roundName == "Semifinals" }
    }
    var championshipGame: SharedGame? {
        games.first { $0.roundName == "Championship" || $0.roundName == "National Championship" }
    }
}

// MARK: - Widget

struct BracketWidget: Widget {
    let kind = "BracketWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BracketProvider()) { entry in
            BracketWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tournament Bracket")
        .description("Visual bracket tree — left, right & center like the real thing")
        .supportedFamilies([.systemLarge, .systemExtraLarge])
    }
}

// MARK: - Main View

struct BracketWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: BracketEntry

    var body: some View {
        VStack(spacing: 0) {
            header
            switch family {
            case .systemExtraLarge:
                fullBracket
            default:
                halfBracket
            }
        }
        .padding(6)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "trophy.fill").font(.system(size: 9)).foregroundStyle(.yellow)
            Text("NCAA Tournament").font(.system(size: 10, weight: .bold))
            Spacer()
            if !entry.liveGames.isEmpty {
                HStack(spacing: 2) {
                    Circle().fill(.red).frame(width: 4, height: 4)
                    Text("\(entry.liveGames.count) LIVE").font(.system(size: 7, weight: .heavy)).foregroundStyle(.red)
                }
            }
        }
        .padding(.bottom, 3)
    }

    // MARK: - Large: Left Region → Center (FF/Champ) ← Right Region

    private var halfBracket: some View {
        let r = entry.regions
        return HStack(spacing: 0) {
            // Left region bracket (reads left → right)
            if r.count >= 1 {
                leftRegion(r[0])
            }

            // Center: Final Four + Trophy + Championship
            centerColumn

            // Right region bracket (reads right → left, mirrored)
            if r.count >= 2 {
                rightRegion(r[1])
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Extra Large: Full bracket — top half and bottom half

    private var fullBracket: some View {
        let r = entry.regions
        return VStack(spacing: 2) {
            // Top half
            HStack(spacing: 0) {
                if r.count >= 1 { leftRegion(r[0]) }
                topCenterColumn
                if r.count >= 2 { rightRegion(r[1]) }
            }
            .frame(maxHeight: .infinity)

            // Center trophy
            HStack {
                Spacer()
                Image(systemName: "trophy.fill").font(.system(size: 14)).foregroundStyle(.yellow)
                if let champ = entry.championshipGame {
                    matchupBox(champ)
                        .frame(width: 80)
                }
                Image(systemName: "trophy.fill").font(.system(size: 14)).foregroundStyle(.yellow)
                Spacer()
            }
            .padding(.vertical, 2)

            // Bottom half
            HStack(spacing: 0) {
                if r.count >= 3 { leftRegion(r[2]) }
                bottomCenterColumn
                if r.count >= 4 { rightRegion(r[3]) }
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Left Region (normal direction: early rounds → later rounds)

    private func leftRegion(_ region: String) -> some View {
        let rounds = entry.roundsFor(region: region)
        return VStack(spacing: 0) {
            regionLabel(region)
            HStack(alignment: .center, spacing: 0) {
                ForEach(Array(rounds.enumerated()), id: \.offset) { idx, games in
                    roundColumn(games: games, roundIdx: idx)
                    if idx < rounds.count - 1 { connectors(count: games.count, roundIdx: idx) }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Right Region (mirrored: later rounds ← early rounds)

    private func rightRegion(_ region: String) -> some View {
        let rounds = entry.roundsFor(region: region)
        return VStack(spacing: 0) {
            regionLabel(region)
            HStack(alignment: .center, spacing: 0) {
                ForEach(Array(rounds.enumerated().reversed()), id: \.offset) { idx, games in
                    if idx < rounds.count - 1 { mirroredConnectors(count: games.count, roundIdx: idx) }
                    roundColumn(games: games, roundIdx: idx)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Center Columns

    private var centerColumn: some View {
        VStack(spacing: 4) {
            Spacer()
            let ff = entry.finalFourGames
            ForEach(ff) { g in matchupBox(g).frame(width: 65) }
            Image(systemName: "trophy.fill").font(.system(size: 12)).foregroundStyle(.yellow)
            if let champ = entry.championshipGame {
                matchupBox(champ).frame(width: 65)
            }
            Spacer()
        }
        .frame(width: 70)
    }

    private var topCenterColumn: some View {
        VStack(spacing: 2) {
            Spacer()
            let ff = entry.finalFourGames
            if let g = ff.first { matchupBox(g).frame(width: 70) }
            else { tbdSlot }
            Spacer()
        }
        .frame(width: 76)
    }

    private var bottomCenterColumn: some View {
        VStack(spacing: 2) {
            Spacer()
            let ff = entry.finalFourGames
            if ff.count > 1 { matchupBox(ff[1]).frame(width: 70) }
            else { tbdSlot }
            Spacer()
        }
        .frame(width: 76)
    }

    private var tbdSlot: some View {
        RoundedRectangle(cornerRadius: 2)
            .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
            .frame(width: 60, height: 16)
            .overlay(Text("TBD").font(.system(size: 6)).foregroundStyle(.tertiary))
    }

    // MARK: - Round Column

    private func roundColumn(games: [SharedGame], roundIdx: Int) -> some View {
        let sp: CGFloat
        switch roundIdx {
        case 0: sp = 2
        case 1: sp = 18
        case 2: sp = 42
        case 3: sp = 90
        default: sp = 2
        }
        return VStack(spacing: sp) {
            ForEach(games) { g in matchupBox(g) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Connectors (left side: coming from the right edge of matchups)

    private func connectors(count: Int, roundIdx: Int) -> some View {
        let pairs = count / 2
        let sp: CGFloat
        switch roundIdx {
        case 0: sp = 2
        case 1: sp = 18
        case 2: sp = 42
        default: sp = 2
        }

        return VStack(spacing: sp + 14) {
            ForEach(0..<max(pairs, 1), id: \.self) { _ in
                connector(direction: .right)
            }
        }
        .frame(maxHeight: .infinity)
        .frame(width: 8)
    }

    private func mirroredConnectors(count: Int, roundIdx: Int) -> some View {
        let pairs = count / 2
        let sp: CGFloat
        switch roundIdx {
        case 0: sp = 2
        case 1: sp = 18
        case 2: sp = 42
        default: sp = 2
        }

        return VStack(spacing: sp + 14) {
            ForEach(0..<max(pairs, 1), id: \.self) { _ in
                connector(direction: .left)
            }
        }
        .frame(maxHeight: .infinity)
        .frame(width: 8)
    }

    enum ConnectorDir { case left, right }

    private func connector(direction: ConnectorDir) -> some View {
        // Draws ┐     or     ┌
        //       ├──   or  ──┤
        //       ┘     or     └
        let lineColor = Color.secondary.opacity(0.3)
        let lineW: CGFloat = 0.5

        return HStack(spacing: 0) {
            if direction == .left {
                // Horizontal out to the left
                Rectangle().fill(lineColor).frame(width: 3, height: lineW)
            }

            // Vertical bar with top/bottom hooks
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    if direction == .right {
                        Spacer(minLength: 0)
                        Rectangle().fill(lineColor).frame(width: 3, height: lineW)
                    } else {
                        Rectangle().fill(lineColor).frame(width: 3, height: lineW)
                        Spacer(minLength: 0)
                    }
                }
                Rectangle().fill(lineColor).frame(width: lineW, height: 12)
                HStack(spacing: 0) {
                    if direction == .right {
                        Spacer(minLength: 0)
                        Rectangle().fill(lineColor).frame(width: 3, height: lineW)
                    } else {
                        Rectangle().fill(lineColor).frame(width: 3, height: lineW)
                        Spacer(minLength: 0)
                    }
                }
            }

            if direction == .right {
                // Horizontal out to the right
                Rectangle().fill(lineColor).frame(width: 3, height: lineW)
            }
        }
    }

    // MARK: - Region Label

    private func regionLabel(_ region: String) -> some View {
        Text(region.uppercased())
            .font(.system(size: 7, weight: .heavy))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 1)
    }

    // MARK: - Matchup Box

    private func matchupBox(_ game: SharedGame) -> some View {
        VStack(spacing: 0) {
            teamLine(seed: game.awaySeed, abbr: game.awayAbbreviation, score: game.awayScore,
                     winning: aLeads(game), live: game.isLive, done: game.isFinal)
            Rectangle().fill(game.isLive ? Color.red.opacity(0.5) : Color.secondary.opacity(0.15)).frame(height: 0.5)
            teamLine(seed: game.homeSeed, abbr: game.homeAbbreviation, score: game.homeScore,
                     winning: hLeads(game), live: game.isLive, done: game.isFinal)
        }
        .background(RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: .windowBackgroundColor).opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(game.isLive ? Color.red.opacity(0.6) : Color.secondary.opacity(0.12), lineWidth: game.isLive ? 1 : 0.5))
    }

    private func teamLine(seed: Int?, abbr: String, score: String, winning: Bool, live: Bool, done: Bool) -> some View {
        HStack(spacing: 1) {
            if let s = seed {
                Text("\(s)").font(.system(size: 6, weight: .medium, design: .monospaced)).foregroundStyle(.secondary).frame(width: 8, alignment: .trailing)
            }
            Text(abbr).font(.system(size: 7, weight: winning ? .bold : .regular)).lineLimit(1)
            Spacer(minLength: 0)
            if live || done {
                Text(score).font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundStyle(live ? .red : (winning ? .primary : .secondary))
            }
        }
        .padding(.horizontal, 2).padding(.vertical, 1)
        .background(winning && done ? Color.green.opacity(0.06) : Color.clear)
    }

    private func aLeads(_ g: SharedGame) -> Bool { guard let a = g.awayScoreInt, let h = g.homeScoreInt else { return false }; return a > h }
    private func hLeads(_ g: SharedGame) -> Bool { guard let a = g.awayScoreInt, let h = g.homeScoreInt else { return false }; return h > a }
}

// MARK: - Sample Data

private let sampleBracketGames: [SharedGame] = [
    // East region
    SharedGame(id: "s1", awayTeam: "Duke", awayAbbreviation: "DUKE", awayScore: "71", awaySeed: 1, awayLogo: nil, awayColor: nil, homeTeam: "Siena", homeAbbreviation: "SIE", homeScore: "65", homeSeed: 16, homeLogo: nil, homeColor: nil, state: "post", detail: "Final", shortDetail: "Final", period: 2, displayClock: nil, startDate: nil, roundName: "1st Round", regionName: "East", broadcast: nil, isUpset: false),
    SharedGame(id: "s2", awayTeam: "MSU", awayAbbreviation: "MSU", awayScore: "92", awaySeed: 3, awayLogo: nil, awayColor: nil, homeTeam: "NDSU", homeAbbreviation: "NDSU", homeScore: "67", homeSeed: 14, homeLogo: nil, homeColor: nil, state: "post", detail: "Final", shortDetail: "Final", period: 2, displayClock: nil, startDate: nil, roundName: "1st Round", regionName: "East", broadcast: nil, isUpset: false),
    SharedGame(id: "s3", awayTeam: "Louisville", awayAbbreviation: "LOU", awayScore: "83", awaySeed: 6, awayLogo: nil, awayColor: nil, homeTeam: "USF", homeAbbreviation: "USF", homeScore: "79", homeSeed: 11, homeLogo: nil, homeColor: nil, state: "post", detail: "Final", shortDetail: "Final", period: 2, displayClock: nil, startDate: nil, roundName: "1st Round", regionName: "East", broadcast: nil, isUpset: false),
    SharedGame(id: "s4", awayTeam: "TCU", awayAbbreviation: "TCU", awayScore: "66", awaySeed: 9, awayLogo: nil, awayColor: nil, homeTeam: "Ohio St", homeAbbreviation: "OSU", homeScore: "64", homeSeed: 8, homeLogo: nil, homeColor: nil, state: "post", detail: "Final", shortDetail: "Final", period: 2, displayClock: nil, startDate: nil, roundName: "1st Round", regionName: "East", broadcast: nil, isUpset: true),
    // West region
    SharedGame(id: "s5", awayTeam: "Texas", awayAbbreviation: "TEX", awayScore: "79", awaySeed: 11, awayLogo: nil, awayColor: nil, homeTeam: "BYU", homeAbbreviation: "BYU", homeScore: "71", homeSeed: 6, homeLogo: nil, homeColor: nil, state: "post", detail: "Final", shortDetail: "Final", period: 2, displayClock: nil, startDate: nil, roundName: "1st Round", regionName: "West", broadcast: nil, isUpset: true),
    SharedGame(id: "s6", awayTeam: "Arkansas", awayAbbreviation: "ARK", awayScore: "97", awaySeed: 4, awayLogo: nil, awayColor: nil, homeTeam: "Hawaii", homeAbbreviation: "HAW", homeScore: "78", homeSeed: 13, homeLogo: nil, homeColor: nil, state: "post", detail: "Final", shortDetail: "Final", period: 2, displayClock: nil, startDate: nil, roundName: "1st Round", regionName: "West", broadcast: nil, isUpset: false),
    SharedGame(id: "s7", awayTeam: "Gonzaga", awayAbbreviation: "GONZ", awayScore: "0", awaySeed: 3, awayLogo: nil, awayColor: nil, homeTeam: "Kennesaw", homeAbbreviation: "KENN", homeScore: "0", homeSeed: 14, homeLogo: nil, homeColor: nil, state: "pre", detail: "7:10 PM", shortDetail: "7:10", period: 0, displayClock: nil, startDate: nil, roundName: "1st Round", regionName: "West", broadcast: nil, isUpset: false),
    SharedGame(id: "s8", awayTeam: "HPU", awayAbbreviation: "HPU", awayScore: "83", awaySeed: 12, awayLogo: nil, awayColor: nil, homeTeam: "Wisconsin", homeAbbreviation: "WIS", homeScore: "82", homeSeed: 5, homeLogo: nil, homeColor: nil, state: "post", detail: "Final", shortDetail: "Final", period: 2, displayClock: nil, startDate: nil, roundName: "1st Round", regionName: "West", broadcast: nil, isUpset: true),
    // South
    SharedGame(id: "s9", awayTeam: "Nebraska", awayAbbreviation: "NEB", awayScore: "76", awaySeed: 4, awayLogo: nil, awayColor: nil, homeTeam: "Troy", homeAbbreviation: "TROY", homeScore: "47", homeSeed: 13, homeLogo: nil, homeColor: nil, state: "post", detail: "Final", shortDetail: "Final", period: 2, displayClock: nil, startDate: nil, roundName: "1st Round", regionName: "South", broadcast: nil, isUpset: false),
    SharedGame(id: "s10", awayTeam: "Vanderbilt", awayAbbreviation: "VAN", awayScore: "78", awaySeed: 5, awayLogo: nil, awayColor: nil, homeTeam: "McNeese", homeAbbreviation: "MCN", homeScore: "68", homeSeed: 12, homeLogo: nil, homeColor: nil, state: "post", detail: "Final", shortDetail: "Final", period: 2, displayClock: nil, startDate: nil, roundName: "1st Round", regionName: "South", broadcast: nil, isUpset: false),
    // Midwest
    SharedGame(id: "s11", awayTeam: "Michigan", awayAbbreviation: "MICH", awayScore: "101", awaySeed: 1, awayLogo: nil, awayColor: nil, homeTeam: "Howard", homeAbbreviation: "HOW", homeScore: "80", homeSeed: 16, homeLogo: nil, homeColor: nil, state: "post", detail: "Final", shortDetail: "Final", period: 2, displayClock: nil, startDate: nil, roundName: "1st Round", regionName: "Midwest", broadcast: nil, isUpset: false),
    SharedGame(id: "s12", awayTeam: "Georgia", awayAbbreviation: "UGA", awayScore: "0", awaySeed: 8, awayLogo: nil, awayColor: nil, homeTeam: "Saint Louis", homeAbbreviation: "SLU", homeScore: "0", homeSeed: 9, homeLogo: nil, homeColor: nil, state: "pre", detail: "9:40 PM", shortDetail: "9:40", period: 0, displayClock: nil, startDate: nil, roundName: "1st Round", regionName: "Midwest", broadcast: nil, isUpset: false),
]
