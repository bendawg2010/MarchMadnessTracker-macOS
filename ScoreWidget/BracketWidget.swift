import WidgetKit
import SwiftUI

// MARK: - Bracket Widget Provider

struct BracketProvider: TimelineProvider {
    func placeholder(in context: Context) -> BracketEntry {
        BracketEntry(date: Date(), games: sampleGames)
    }

    func getSnapshot(in context: Context, completion: @escaping (BracketEntry) -> Void) {
        if context.isPreview {
            completion(BracketEntry(date: Date(), games: sampleGames))
            return
        }
        Task {
            let games = await fetchScores()
            completion(BracketEntry(date: Date(), games: games))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BracketEntry>) -> Void) {
        Task {
            let games = await fetchScores()
            let entry = BracketEntry(date: Date(), games: games.isEmpty ? sampleGames : games)
            let hasLive = games.contains { $0.isLive }
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: hasLive ? 2 : 15, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    private func fetchScores() async -> [SharedGame] {
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/scoreboard?groups=100") else {
            return sampleGames
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let events = json?["events"] as? [[String: Any]] else { return sampleGames }
            return events.compactMap { event -> SharedGame? in
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
        } catch {
            return sampleGames
        }
    }
}

struct BracketEntry: TimelineEntry {
    let date: Date
    let games: [SharedGame]

    var liveGames: [SharedGame] { games.filter { $0.isLive } }

    /// Organize games into bracket structure by region and round
    func gamesForRegion(_ region: String) -> [String: [SharedGame]] {
        let regionGames = games.filter { $0.regionName == region }
        return Dictionary(grouping: regionGames) { $0.roundName ?? "Unknown" }
    }

    var regions: [String] {
        let allRegions = games.compactMap { $0.regionName }
        // Preserve a stable order
        var seen = Set<String>()
        return allRegions.filter { seen.insert($0).inserted }
    }

    var finalFourGames: [SharedGame] {
        games.filter { $0.roundName == "Final Four" || $0.roundName == "Semifinals" }
    }

    var championshipGame: SharedGame? {
        games.first { $0.roundName == "Championship" || $0.roundName == "National Championship" }
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
        .description("Visual March Madness bracket with matchup lines")
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
    }
}

// MARK: - Visual Bracket Widget View

struct BracketWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: BracketEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumBracket
        case .systemLarge:
            largeBracket
        case .systemExtraLarge:
            extraLargeBracket
        default:
            largeBracket
        }
    }

    // MARK: - Medium: Single region mini-bracket

    private var mediumBracket: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.yellow)
                Text("March Madness")
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

            if let region = entry.regions.first {
                miniBracketRegion(region)
            } else {
                // Show available games as bracket pairs
                miniBracketFromGames(Array(entry.games.prefix(8)))
            }
        }
        .padding(2)
    }

    // MARK: - Large: Two regions side by side

    private var largeBracket: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
                Text("March Madness Bracket")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                if !entry.liveGames.isEmpty {
                    HStack(spacing: 2) {
                        Circle().fill(.red).frame(width: 5, height: 5)
                        Text("\(entry.liveGames.count) LIVE")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.red)
                    }
                }
            }

            if entry.regions.count >= 2 {
                HStack(spacing: 8) {
                    bracketColumn(region: entry.regions[0])
                    bracketConnectorColumn(games: entry.finalFourGames, championship: entry.championshipGame)
                    bracketColumn(region: entry.regions[1], flipped: true)
                }
            } else {
                miniBracketFromGames(entry.games)
            }
        }
        .padding(2)
    }

    // MARK: - Extra Large: Full 4-region bracket

    private var extraLargeBracket: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.yellow)
                Text("NCAA Tournament Bracket")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                if !entry.liveGames.isEmpty {
                    HStack(spacing: 3) {
                        Circle().fill(.red).frame(width: 5, height: 5)
                        Text("\(entry.liveGames.count) LIVE")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.bottom, 4)

            // Top half: Region 1 (left) -> Final Four <- Region 2 (right)
            HStack(spacing: 0) {
                if entry.regions.count >= 1 {
                    fullBracketRegion(entry.regions[0])
                }
                Spacer(minLength: 4)
                // Center: Final Four + Championship
                centerBracket
                Spacer(minLength: 4)
                if entry.regions.count >= 2 {
                    fullBracketRegion(entry.regions[1], flipped: true)
                }
            }
            .frame(maxHeight: .infinity)

            Divider().padding(.horizontal, 8)

            // Bottom half: Region 3 (left) -> Final Four <- Region 4 (right)
            HStack(spacing: 0) {
                if entry.regions.count >= 3 {
                    fullBracketRegion(entry.regions[2])
                }
                Spacer(minLength: 4)
                // Center trophy
                VStack {
                    Spacer()
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.yellow)
                    Spacer()
                }
                .frame(width: 50)
                Spacer(minLength: 4)
                if entry.regions.count >= 4 {
                    fullBracketRegion(entry.regions[3], flipped: true)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(4)
    }

    // MARK: - Bracket Components

    /// A single region column showing matchups with connecting lines
    private func bracketColumn(region: String, flipped: Bool = false) -> some View {
        let regionGames = entry.gamesForRegion(region)
        let roundOrder = ["1st Round", "2nd Round", "Sweet 16", "Elite 8"]

        return VStack(spacing: 2) {
            Text(region)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            GeometryReader { geo in
                HStack(spacing: 2) {
                    if flipped {
                        laterRounds(regionGames: regionGames, roundOrder: roundOrder, height: geo.size.height, flipped: true)
                        earlyRound(regionGames: regionGames, roundName: roundOrder[0], height: geo.size.height)
                    } else {
                        earlyRound(regionGames: regionGames, roundName: roundOrder[0], height: geo.size.height)
                        laterRounds(regionGames: regionGames, roundOrder: roundOrder, height: geo.size.height, flipped: false)
                    }
                }
            }
        }
    }

    private func earlyRound(regionGames: [String: [SharedGame]], roundName: String, height: CGFloat) -> some View {
        let games = regionGames[roundName] ?? []
        let slotHeight = max(height / max(CGFloat(games.count), 4), 14)

        return VStack(spacing: 1) {
            ForEach(Array(games.prefix(8))) { game in
                matchupCell(game, compact: true)
                    .frame(height: slotHeight - 1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func laterRounds(regionGames: [String: [SharedGame]], roundOrder: [String], height: CGFloat, flipped: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(1..<roundOrder.count, id: \.self) { i in
                let games = regionGames[roundOrder[i]] ?? []
                let slotHeight = max(height / max(CGFloat(games.count), 1), 20)

                VStack(spacing: 2) {
                    ForEach(Array(games.prefix(4))) { game in
                        matchupCell(game, compact: false)
                            .frame(height: slotHeight - 2)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Full region bracket with lines for extra-large widget
    private func fullBracketRegion(_ region: String, flipped: Bool = false) -> some View {
        let regionGames = entry.gamesForRegion(region)
        let roundOrder = ["1st Round", "2nd Round", "Sweet 16", "Elite 8"]

        return VStack(spacing: 0) {
            Text(region)
                .font(.system(size: 7, weight: .heavy))
                .foregroundStyle(.orange)
                .textCase(.uppercase)

            GeometryReader { geo in
                let rounds: [[SharedGame]] = roundOrder.map { regionGames[$0] ?? [] }
                let totalHeight = geo.size.height
                let columnWidth = geo.size.width / CGFloat(roundOrder.count)

                ZStack(alignment: .topLeading) {
                    // Draw bracket lines
                    BracketLinesShape(
                        rounds: rounds.map { $0.count },
                        totalHeight: totalHeight,
                        columnWidth: columnWidth,
                        flipped: flipped
                    )
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)

                    // Draw matchup cells
                    HStack(spacing: 0) {
                        if flipped {
                            ForEach((0..<roundOrder.count).reversed(), id: \.self) { roundIdx in
                                roundColumn(games: rounds[roundIdx], totalHeight: totalHeight)
                                    .frame(width: columnWidth)
                            }
                        } else {
                            ForEach(0..<roundOrder.count, id: \.self) { roundIdx in
                                roundColumn(games: rounds[roundIdx], totalHeight: totalHeight)
                                    .frame(width: columnWidth)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func roundColumn(games: [SharedGame], totalHeight: CGFloat) -> some View {
        let count = max(games.count, 1)
        let slotHeight = totalHeight / CGFloat(count)

        return VStack(spacing: 0) {
            ForEach(Array(games.enumerated()), id: \.element.id) { _, game in
                matchupCell(game, compact: games.count > 4)
                    .frame(height: slotHeight)
            }
            if games.isEmpty {
                Spacer()
            }
        }
    }

    /// Center column showing Final Four + Championship
    private var centerBracket: some View {
        VStack(spacing: 4) {
            Spacer()

            // Final Four
            ForEach(entry.finalFourGames) { game in
                matchupCell(game, compact: false)
                    .frame(height: 28)
            }

            // Championship
            if let champ = entry.championshipGame {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
                matchupCell(champ, compact: false)
                    .frame(height: 28)
            } else {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.yellow.opacity(0.5))
            }

            Spacer()
        }
        .frame(width: 60)
    }

    private func bracketConnectorColumn(games: [SharedGame], championship: SharedGame?) -> some View {
        VStack(spacing: 4) {
            Spacer()
            ForEach(games) { game in
                matchupCell(game, compact: false)
                    .frame(height: 24)
            }
            if let champ = championship {
                VStack(spacing: 2) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                    matchupCell(champ, compact: false)
                        .frame(height: 24)
                }
            } else {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.yellow.opacity(0.4))
            }
            Spacer()
        }
        .frame(width: 60)
    }

    // MARK: - Matchup Cell

    private func matchupCell(_ game: SharedGame, compact: Bool) -> some View {
        let fontSize: CGFloat = compact ? 7 : 8
        let seedSize: CGFloat = compact ? 6 : 7

        return VStack(spacing: 0) {
            // Top team (away)
            HStack(spacing: 2) {
                if let seed = game.awaySeed {
                    Text("\(seed)")
                        .font(.system(size: seedSize, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 10, alignment: .trailing)
                } else {
                    Spacer().frame(width: 10)
                }
                Text(game.awayAbbreviation)
                    .font(.system(size: fontSize, weight: awayWins(game) ? .bold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if game.isLive || game.isFinal {
                    Text(game.awayScore)
                        .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                        .foregroundStyle(game.isLive ? .red : (awayWins(game) ? .primary : .secondary))
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
            .background(awayWins(game) && game.isFinal ? Color.green.opacity(0.08) : Color.clear)

            // Divider line
            Rectangle()
                .fill(game.isLive ? Color.red.opacity(0.5) : Color.secondary.opacity(0.2))
                .frame(height: 0.5)

            // Bottom team (home)
            HStack(spacing: 2) {
                if let seed = game.homeSeed {
                    Text("\(seed)")
                        .font(.system(size: seedSize, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 10, alignment: .trailing)
                } else {
                    Spacer().frame(width: 10)
                }
                Text(game.homeAbbreviation)
                    .font(.system(size: fontSize, weight: homeWins(game) ? .bold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if game.isLive || game.isFinal {
                    Text(game.homeScore)
                        .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                        .foregroundStyle(game.isLive ? .red : (homeWins(game) ? .primary : .secondary))
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
            .background(homeWins(game) && game.isFinal ? Color.green.opacity(0.08) : Color.clear)
        }
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.windowBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(game.isLive ? Color.red.opacity(0.6) : Color.secondary.opacity(0.15), lineWidth: game.isLive ? 1 : 0.5)
        )
    }

    // MARK: - Mini bracket (fallback when we don't have region data)

    private func miniBracketRegion(_ region: String) -> some View {
        let regionGames = entry.gamesForRegion(region)
        let allGames: [SharedGame] = regionGames.values.flatMap { $0 }
        return miniBracketFromGames(allGames)
    }

    private func miniBracketFromGames(_ allGames: [SharedGame]) -> some View {
        let gameArray: [SharedGame] = Array(allGames.prefix(8))

        return GeometryReader { geo in
            HStack(spacing: 4) {
                // Left column: all matchups stacked
                VStack(spacing: 2) {
                    ForEach(gameArray) { game in
                        matchupCell(game, compact: true)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)

                // Connector lines
                BracketLinesView(pairCount: gameArray.count / 2, height: geo.size.height)
                    .frame(width: 12)

                // Right column: winners / TBD
                VStack(spacing: 4) {
                    ForEach(0..<max(gameArray.count / 2, 1), id: \.self) { i in
                        let idx = i * 2
                        if idx < gameArray.count && gameArray[idx].isFinal {
                            matchupCell(gameArray[idx], compact: true)
                        } else {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                                .frame(height: 18)
                                .overlay(
                                    Text("TBD")
                                        .font(.system(size: 7))
                                        .foregroundStyle(.tertiary)
                                )
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Helpers

    private func awayWins(_ game: SharedGame) -> Bool {
        guard let a = game.awayScoreInt, let h = game.homeScoreInt else { return false }
        return a > h
    }

    private func homeWins(_ game: SharedGame) -> Bool {
        guard let a = game.awayScoreInt, let h = game.homeScoreInt else { return false }
        return h > a
    }
}

// MARK: - Bracket Lines Shape (connects matchups visually)

struct BracketLinesShape: Shape {
    let rounds: [Int] // number of games per round
    let totalHeight: CGFloat
    let columnWidth: CGFloat
    let flipped: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()

        for roundIdx in 0..<max(0, rounds.count - 1) {
            let currentCount = rounds[roundIdx]
            let nextCount = rounds[roundIdx + 1]
            guard currentCount > 0, nextCount > 0 else { continue }

            let currentSlotH = totalHeight / CGFloat(currentCount)
            let nextSlotH = totalHeight / CGFloat(nextCount)

            for i in stride(from: 0, to: currentCount, by: 2) {
                let nextIdx = i / 2
                guard nextIdx < nextCount else { continue }

                let topMid = currentSlotH * CGFloat(i) + currentSlotH / 2
                let bottomMid = currentSlotH * CGFloat(i + 1) + currentSlotH / 2
                let targetMid = nextSlotH * CGFloat(nextIdx) + nextSlotH / 2

                let x1: CGFloat
                let x2: CGFloat
                if flipped {
                    x1 = CGFloat(rounds.count - 1 - roundIdx) * columnWidth
                    x2 = CGFloat(rounds.count - 2 - roundIdx) * columnWidth + columnWidth
                } else {
                    x1 = CGFloat(roundIdx) * columnWidth + columnWidth
                    x2 = CGFloat(roundIdx + 1) * columnWidth
                }

                let midX = (x1 + x2) / 2

                // Top game -> connector
                path.move(to: CGPoint(x: x1, y: topMid))
                path.addLine(to: CGPoint(x: midX, y: topMid))
                path.addLine(to: CGPoint(x: midX, y: bottomMid))
                path.addLine(to: CGPoint(x: x1, y: bottomMid))

                // Connector -> next round
                path.move(to: CGPoint(x: midX, y: targetMid))
                path.addLine(to: CGPoint(x: x2, y: targetMid))
            }
        }

        return path
    }
}

// MARK: - Simple bracket lines view for mini bracket

struct BracketLinesView: View {
    let pairCount: Int
    let height: CGFloat

    var body: some View {
        Canvas { context, size in
            let pairHeight = size.height / CGFloat(max(pairCount, 1))

            for i in 0..<pairCount {
                let topY = pairHeight * CGFloat(i) + pairHeight * 0.25
                let bottomY = pairHeight * CGFloat(i) + pairHeight * 0.75
                let midY = (topY + bottomY) / 2

                var line = Path()
                // Right edge of left games
                line.move(to: CGPoint(x: 0, y: topY))
                line.addLine(to: CGPoint(x: size.width * 0.5, y: topY))
                line.addLine(to: CGPoint(x: size.width * 0.5, y: bottomY))
                line.addLine(to: CGPoint(x: 0, y: bottomY))

                // To next round
                line.move(to: CGPoint(x: size.width * 0.5, y: midY))
                line.addLine(to: CGPoint(x: size.width, y: midY))

                context.stroke(line, with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)
            }
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
