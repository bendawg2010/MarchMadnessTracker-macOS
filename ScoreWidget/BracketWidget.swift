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
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/scoreboard?groups=100") else {
            return []
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let events = json?["events"] as? [[String: Any]] else { return [] }
            return events.compactMap { parseEvent($0) }
        } catch {
            return []
        }
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
        let notes = event["notes"] as? [[String: Any]]
        let headline = notes?.first?["headline"] as? String
        let parts = headline?.components(separatedBy: " - ") ?? []

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
            regionName: parts.count >= 2 ? parts[parts.count - 2].trimmingCharacters(in: .whitespaces) : nil,
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
    var activeAndFinished: [SharedGame] { games.filter { $0.isLive || $0.isFinal } }

    // Organized by region
    var regions: [String] {
        var seen = Set<String>()
        return games.compactMap { $0.regionName }.filter { seen.insert($0).inserted }
    }

    func gamesFor(region: String, round: String) -> [SharedGame] {
        games.filter { $0.regionName == region && $0.roundName == round }
    }

    func gamesFor(round: String) -> [SharedGame] {
        games.filter { $0.roundName == round }
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
        .description("Live NCAA bracket with scores and matchup lines")
        .supportedFamilies([.systemLarge, .systemExtraLarge])
    }
}

// MARK: - Main Widget View

struct BracketWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: BracketEntry

    var body: some View {
        switch family {
        case .systemExtraLarge:
            fullBracketView
        default:
            regionBracketView
        }
    }

    // MARK: - Large: Show one half of the bracket (2 regions feeding into Final Four)

    private var regionBracketView: some View {
        VStack(spacing: 0) {
            bracketHeader

            if entry.regions.count >= 2 {
                // Two regions → Final Four style
                GeometryReader { geo in
                    twoRegionBracket(size: geo.size)
                }
            } else {
                // Just show all games as a bracket tree
                GeometryReader { geo in
                    allGamesBracket(size: geo.size)
                }
            }
        }
        .padding(6)
    }

    // MARK: - Extra Large: Full 4-region bracket

    private var fullBracketView: some View {
        VStack(spacing: 0) {
            bracketHeader

            GeometryReader { geo in
                let halfH = (geo.size.height - 4) / 2
                VStack(spacing: 4) {
                    // Top: regions 0 & 1
                    topHalfBracket(size: CGSize(width: geo.size.width, height: halfH))
                    // Bottom: regions 2 & 3
                    bottomHalfBracket(size: CGSize(width: geo.size.width, height: halfH))
                }
            }
        }
        .padding(6)
    }

    // MARK: - Header

    private var bracketHeader: some View {
        HStack(spacing: 4) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 10))
                .foregroundStyle(.yellow)
            Text("NCAA Tournament")
                .font(.system(size: 11, weight: .bold))
            Spacer()
            if !entry.liveGames.isEmpty {
                HStack(spacing: 3) {
                    Circle().fill(.red).frame(width: 5, height: 5)
                    Text("\(entry.liveGames.count) LIVE")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Two-region bracket (Large widget)

    private func twoRegionBracket(size: CGSize) -> some View {
        let r = entry.regions
        let centerW: CGFloat = 70
        let sideW = (size.width - centerW) / 2

        return HStack(spacing: 0) {
            // Left region
            regionColumn(
                region: r.count > 0 ? r[0] : "",
                width: sideW,
                height: size.height,
                flipped: false
            )

            // Center: Final Four + Championship
            centerColumn(width: centerW, height: size.height)

            // Right region
            regionColumn(
                region: r.count > 1 ? r[1] : "",
                width: sideW,
                height: size.height,
                flipped: true
            )
        }
    }

    // MARK: - Top/Bottom half for Extra Large

    private func topHalfBracket(size: CGSize) -> some View {
        let r = entry.regions
        let centerW: CGFloat = 80
        let sideW = (size.width - centerW) / 2

        return HStack(spacing: 0) {
            regionColumn(
                region: r.count > 0 ? r[0] : "",
                width: sideW,
                height: size.height,
                flipped: false
            )

            // Final Four slot
            VStack {
                Spacer()
                let ff = entry.gamesFor(round: "Final Four") + entry.gamesFor(round: "Semifinals")
                if let game = ff.first {
                    matchupBox(game, width: centerW - 8)
                } else {
                    tbdBox(width: centerW - 8)
                }

                // Championship
                let champ = entry.gamesFor(round: "Championship") + entry.gamesFor(round: "National Championship")
                if let game = champ.first {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.yellow)
                        .padding(.top, 4)
                    matchupBox(game, width: centerW - 8)
                } else {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.yellow.opacity(0.4))
                        .padding(.top, 6)
                }
                Spacer()
            }
            .frame(width: centerW)

            regionColumn(
                region: r.count > 1 ? r[1] : "",
                width: sideW,
                height: size.height,
                flipped: true
            )
        }
    }

    private func bottomHalfBracket(size: CGSize) -> some View {
        let r = entry.regions
        let centerW: CGFloat = 80
        let sideW = (size.width - centerW) / 2

        return HStack(spacing: 0) {
            regionColumn(
                region: r.count > 2 ? r[2] : "",
                width: sideW,
                height: size.height,
                flipped: false
            )

            VStack {
                Spacer()
                let ff = entry.gamesFor(round: "Final Four") + entry.gamesFor(round: "Semifinals")
                if ff.count > 1 {
                    matchupBox(ff[1], width: centerW - 8)
                } else {
                    tbdBox(width: centerW - 8)
                }
                Spacer()
            }
            .frame(width: centerW)

            regionColumn(
                region: r.count > 3 ? r[3] : "",
                width: sideW,
                height: size.height,
                flipped: true
            )
        }
    }

    // MARK: - Region Column: draws round columns + bracket lines

    private func regionColumn(region: String, width: CGFloat, height: CGFloat, flipped: Bool) -> some View {
        let roundNames = ["1st Round", "2nd Round", "Sweet 16", "Elite 8"]
        // Get games per round for this region
        let roundGames: [[SharedGame]] = roundNames.map { round in
            if region.isEmpty { return [] }
            return entry.gamesFor(region: region, round: round)
        }
        // Find which rounds actually have data
        let activeRounds: [(index: Int, games: [SharedGame])] = roundGames.enumerated().compactMap { idx, games in
            games.isEmpty ? nil : (index: idx, games: games)
        }

        let numCols = max(activeRounds.count, 1)
        let colW = width / CGFloat(numCols)

        return VStack(spacing: 0) {
            // Region name
            Text(region.isEmpty ? "" : region.uppercased())
                .font(.system(size: 7, weight: .heavy))
                .foregroundStyle(.orange)
                .frame(height: 10)

            // Bracket content
            ZStack {
                // Lines connecting rounds
                Canvas { context, canvasSize in
                    drawBracketLines(
                        context: &context,
                        size: canvasSize,
                        roundCounts: activeRounds.map { $0.games.count },
                        colWidth: colW,
                        flipped: flipped
                    )
                }

                // Matchup boxes
                HStack(spacing: 0) {
                    let orderedRounds = flipped ? activeRounds.reversed() : activeRounds
                    ForEach(Array(orderedRounds.enumerated()), id: \.offset) { _, roundData in
                        roundCol(games: roundData.games, colWidth: colW, totalHeight: height - 10)
                    }
                    if activeRounds.isEmpty {
                        // No games yet — show placeholder
                        VStack {
                            Spacer()
                            Text("No games yet")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .frame(width: width)
                    }
                }
            }
        }
        .frame(width: width, height: height)
    }

    private func roundCol(games: [SharedGame], colWidth: CGFloat, totalHeight: CGFloat) -> some View {
        let count = max(games.count, 1)
        let slotH = totalHeight / CGFloat(count)

        return VStack(spacing: 0) {
            ForEach(games) { game in
                VStack {
                    Spacer(minLength: 0)
                    matchupBox(game, width: colWidth - 4)
                    Spacer(minLength: 0)
                }
                .frame(height: slotH)
            }
        }
        .frame(width: colWidth)
    }

    // MARK: - Center column for Large widget

    private func centerColumn(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 4) {
            Spacer()

            let ff = entry.gamesFor(round: "Final Four") + entry.gamesFor(round: "Semifinals")
            ForEach(ff) { game in
                matchupBox(game, width: width - 6)
            }
            if ff.isEmpty {
                tbdBox(width: width - 6)
            }

            let champ = entry.gamesFor(round: "Championship") + entry.gamesFor(round: "National Championship")
            if let game = champ.first {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
                matchupBox(game, width: width - 6)
            } else {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.yellow.opacity(0.4))
            }

            Spacer()
        }
        .frame(width: width)
    }

    // MARK: - All games bracket (fallback when no region data)

    private func allGamesBracket(size: CGSize) -> some View {
        let roundNames = ["1st Round", "2nd Round", "Sweet 16", "Elite 8", "Final Four", "Championship"]
        let roundGames: [[SharedGame]] = roundNames.map { entry.gamesFor(round: $0) }
        let activeRounds = roundGames.filter { !$0.isEmpty }
        let numCols = max(activeRounds.count, 1)
        let colW = size.width / CGFloat(numCols)

        return ZStack {
            Canvas { context, canvasSize in
                drawBracketLines(
                    context: &context,
                    size: canvasSize,
                    roundCounts: activeRounds.map { $0.count },
                    colWidth: colW,
                    flipped: false
                )
            }

            HStack(spacing: 0) {
                ForEach(Array(activeRounds.enumerated()), id: \.offset) { _, games in
                    roundCol(games: games, colWidth: colW, totalHeight: size.height)
                }
                if activeRounds.isEmpty {
                    ForEach(entry.games.prefix(8)) { game in
                        matchupBox(game, width: size.width / 2 - 4)
                    }
                }
            }
        }
    }

    // MARK: - Matchup Box (the core bracket cell)

    private func matchupBox(_ game: SharedGame, width: CGFloat) -> some View {
        let isLive = game.isLive
        let isFinal = game.isFinal
        let fs: CGFloat = width < 55 ? 7 : 8
        let seedFs: CGFloat = fs - 1

        return VStack(spacing: 0) {
            // Team 1 (away)
            teamRow(
                seed: game.awaySeed,
                abbr: game.awayAbbreviation,
                score: game.awayScore,
                isWinning: awayLeads(game),
                isLive: isLive,
                isFinal: isFinal,
                fontSize: fs,
                seedFontSize: seedFs
            )

            // Divider
            Rectangle()
                .fill(isLive ? Color.red.opacity(0.6) : Color.secondary.opacity(0.2))
                .frame(height: 0.5)

            // Team 2 (home)
            teamRow(
                seed: game.homeSeed,
                abbr: game.homeAbbreviation,
                score: game.homeScore,
                isWinning: homeLeads(game),
                isLive: isLive,
                isFinal: isFinal,
                fontSize: fs,
                seedFontSize: seedFs
            )

            // Game status bar
            if isLive {
                HStack(spacing: 2) {
                    Circle().fill(.red).frame(width: 3, height: 3)
                    Text(game.shortDetail ?? "LIVE")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 1)
                .background(Color.red.opacity(0.08))
            }
        }
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.windowBackgroundColor).opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(
                    isLive ? Color.red.opacity(0.7) : Color.secondary.opacity(0.15),
                    lineWidth: isLive ? 1.5 : 0.5
                )
        )
    }

    private func teamRow(
        seed: Int?,
        abbr: String,
        score: String,
        isWinning: Bool,
        isLive: Bool,
        isFinal: Bool,
        fontSize: CGFloat,
        seedFontSize: CGFloat
    ) -> some View {
        HStack(spacing: 2) {
            if let seed = seed {
                Text("\(seed)")
                    .font(.system(size: seedFontSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 10, alignment: .trailing)
            } else {
                Spacer().frame(width: 10)
            }
            Text(abbr)
                .font(.system(size: fontSize, weight: isWinning ? .bold : .regular))
                .lineLimit(1)
            Spacer(minLength: 0)
            if isLive || isFinal {
                Text(score)
                    .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(isLive ? .red : (isWinning ? .primary : .secondary))
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 1.5)
        .background(isWinning && isFinal ? Color.green.opacity(0.08) : Color.clear)
    }

    private func tbdBox(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
            .frame(width: width, height: 20)
            .overlay(
                Text("TBD")
                    .font(.system(size: 7))
                    .foregroundStyle(.tertiary)
            )
    }

    // MARK: - Draw bracket connecting lines

    private func drawBracketLines(
        context: inout GraphicsContext,
        size: CGSize,
        roundCounts: [Int],
        colWidth: CGFloat,
        flipped: Bool
    ) {
        guard roundCounts.count >= 2 else { return }

        for i in 0..<(roundCounts.count - 1) {
            let curCount = roundCounts[i]
            let nextCount = roundCounts[i + 1]
            guard curCount > 0, nextCount > 0 else { continue }

            let curSlotH = size.height / CGFloat(curCount)
            let nextSlotH = size.height / CGFloat(nextCount)

            for j in stride(from: 0, to: curCount, by: 2) {
                guard j + 1 < curCount || curCount == 1 else {
                    // Odd game, just draw a line forward
                    let midY = curSlotH * CGFloat(j) + curSlotH / 2
                    let nextIdx = j / 2
                    guard nextIdx < nextCount else { continue }
                    let targetY = nextSlotH * CGFloat(nextIdx) + nextSlotH / 2

                    let col = flipped ? CGFloat(roundCounts.count - 1 - i) : CGFloat(i)
                    let nextCol = flipped ? CGFloat(roundCounts.count - 2 - i) : CGFloat(i + 1)

                    var line = Path()
                    line.move(to: CGPoint(x: (col + (flipped ? 0 : 1)) * colWidth, y: midY))
                    line.addLine(to: CGPoint(x: (nextCol + (flipped ? 1 : 0)) * colWidth, y: targetY))
                    context.stroke(line, with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)
                    continue
                }

                let topMidY = curSlotH * CGFloat(j) + curSlotH / 2
                let botMidY = curSlotH * CGFloat(j + 1) + curSlotH / 2
                let nextIdx = j / 2
                guard nextIdx < nextCount else { continue }
                let targetY = nextSlotH * CGFloat(nextIdx) + nextSlotH / 2

                let col = flipped ? CGFloat(roundCounts.count - 1 - i) : CGFloat(i)
                let nextCol = flipped ? CGFloat(roundCounts.count - 2 - i) : CGFloat(i + 1)

                let x1 = (col + (flipped ? 0 : 1)) * colWidth
                let x2 = (nextCol + (flipped ? 1 : 0)) * colWidth
                let midX = (x1 + x2) / 2

                var line = Path()
                // Horizontal from top game
                line.move(to: CGPoint(x: x1, y: topMidY))
                line.addLine(to: CGPoint(x: midX, y: topMidY))
                // Vertical connector
                line.addLine(to: CGPoint(x: midX, y: botMidY))
                // Horizontal from bottom game
                line.move(to: CGPoint(x: x1, y: botMidY))
                line.addLine(to: CGPoint(x: midX, y: botMidY))
                // Horizontal to next round
                line.move(to: CGPoint(x: midX, y: targetY))
                line.addLine(to: CGPoint(x: x2, y: targetY))

                context.stroke(line, with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)
            }
        }
    }

    // MARK: - Helpers

    private func awayLeads(_ game: SharedGame) -> Bool {
        guard let a = game.awayScoreInt, let h = game.homeScoreInt else { return false }
        return a > h
    }

    private func homeLeads(_ game: SharedGame) -> Bool {
        guard let a = game.awayScoreInt, let h = game.homeScoreInt else { return false }
        return h > a
    }
}

// MARK: - Sample data with enough games to show a bracket

private let sampleBracketGames: [SharedGame] = [
    // East - Sweet 16
    SharedGame(
        id: "b1", awayTeam: "Duke", awayAbbreviation: "DUKE", awayScore: "72",
        awaySeed: 4, awayLogo: nil, awayColor: "003087",
        homeTeam: "UNC", homeAbbreviation: "UNC", homeScore: "68",
        homeSeed: 1, homeLogo: nil, homeColor: "7BAFD4",
        state: "in", detail: "2nd Half - 4:32", shortDetail: "2H 4:32",
        period: 2, displayClock: "4:32", startDate: Date(),
        roundName: "Sweet 16", regionName: "East", broadcast: "CBS",
        isUpset: true
    ),
    SharedGame(
        id: "b2", awayTeam: "Auburn", awayAbbreviation: "AUB", awayScore: "61",
        awaySeed: 2, awayLogo: nil, awayColor: "0C2340",
        homeTeam: "Michigan St", homeAbbreviation: "MSU", homeScore: "55",
        homeSeed: 3, homeLogo: nil, homeColor: "18453B",
        state: "post", detail: "Final", shortDetail: "Final",
        period: 2, displayClock: "0:00", startDate: nil,
        roundName: "Sweet 16", regionName: "East", broadcast: "TBS",
        isUpset: false
    ),
    // East - Elite 8
    SharedGame(
        id: "b3", awayTeam: "TBD", awayAbbreviation: "TBD", awayScore: "0",
        awaySeed: nil, awayLogo: nil, awayColor: nil,
        homeTeam: "Auburn", homeAbbreviation: "AUB", homeScore: "0",
        homeSeed: 2, homeLogo: nil, homeColor: "0C2340",
        state: "pre", detail: "Sat 6:09 PM", shortDetail: "Sat 6:09 PM",
        period: 0, displayClock: nil, startDate: nil,
        roundName: "Elite 8", regionName: "East", broadcast: "CBS",
        isUpset: false
    ),
    // South - Sweet 16
    SharedGame(
        id: "b4", awayTeam: "Kansas", awayAbbreviation: "KU", awayScore: "65",
        awaySeed: 1, awayLogo: nil, awayColor: "0051BA",
        homeTeam: "Kentucky", homeAbbreviation: "UK", homeScore: "58",
        homeSeed: 3, homeLogo: nil, homeColor: "0033A0",
        state: "post", detail: "Final", shortDetail: "Final",
        period: 2, displayClock: "0:00", startDate: nil,
        roundName: "Sweet 16", regionName: "South", broadcast: "TNT",
        isUpset: false
    ),
    SharedGame(
        id: "b5", awayTeam: "Houston", awayAbbreviation: "HOU", awayScore: "58",
        awaySeed: 2, awayLogo: nil, awayColor: "C8102E",
        homeTeam: "Purdue", homeAbbreviation: "PUR", homeScore: "62",
        homeSeed: 4, homeLogo: nil, homeColor: "CFB991",
        state: "in", detail: "2nd Half - 8:15", shortDetail: "2H 8:15",
        period: 2, displayClock: "8:15", startDate: Date(),
        roundName: "Sweet 16", regionName: "South", broadcast: "TBS",
        isUpset: true
    ),
]
