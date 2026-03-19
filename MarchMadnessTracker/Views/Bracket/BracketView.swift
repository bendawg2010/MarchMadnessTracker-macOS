import SwiftUI

struct BracketView: View {
    var poller: ScorePoller
    @State private var selectedRegion: TournamentRegion = .south

    private var bracketGames: [Event] {
        let all = poller.allTournamentGames.isEmpty ? poller.games : poller.allTournamentGames
        // Include games with notes (bracket data) OR games with real teams
        return all.filter { event in
            event.notes?.first?.headline != nil || hasRealTeams(event)
        }
    }

    private func hasRealTeams(_ event: Event) -> Bool {
        guard let comp = event.competition else { return false }
        let real = comp.competitors.filter { !$0.team.abbreviation.isEmpty && $0.team.abbreviation != "TBD" }
        return real.count >= 2
    }

    private var availableRegions: [TournamentRegion] {
        let regions = Set(bracketGames.compactMap { event -> TournamentRegion? in
            guard let regionName = event.regionName else { return nil }
            return TournamentRegion.fromString(regionName)
        })

        var result = TournamentRegion.allCases.filter { regions.contains($0) || $0 == .finalFour }
        let hasFinalFour = bracketGames.contains { event in
            guard let round = event.roundName else { return false }
            let r = TournamentRound.fromString(round)
            return r == .finalFour || r == .championship
        }
        if !hasFinalFour {
            result.removeAll { $0 == .finalFour }
        }

        // If no regions found, show all 4 + Final Four as options
        if result.isEmpty {
            result = [.south, .east, .midwest, .west]
        }

        return result
    }

    private var gamesForSelectedRegion: [Event] {
        if selectedRegion == .finalFour {
            return bracketGames.filter { event in
                guard let round = event.roundName else { return false }
                let r = TournamentRound.fromString(round)
                return r == .finalFour || r == .championship
            }
        }
        let regionGames = bracketGames.filter { event in
            guard let regionName = event.regionName else { return false }
            return TournamentRegion.fromString(regionName) == selectedRegion
        }

        // If no games found for this region, show all bracket games as fallback
        if regionGames.isEmpty && selectedRegion != .finalFour {
            return bracketGames.filter { hasRealTeams($0) }
        }
        return regionGames
    }

    private var gamesByRound: [(TournamentRound, [Event])] {
        let games = gamesForSelectedRegion
        let grouped = Dictionary(grouping: games) { event -> TournamentRound in
            guard let roundName = event.roundName else { return .firstRound }
            return TournamentRound.fromString(roundName) ?? .firstRound
        }
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(spacing: 0) {
            if bracketGames.isEmpty {
                emptyState
            } else {
                // Region picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(availableRegions) { region in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedRegion = region
                                }
                            } label: {
                                Text(region.rawValue)
                                    .font(.caption)
                                    .fontWeight(selectedRegion == region ? .bold : .regular)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(selectedRegion == region ? Color.accentColor : Color.clear)
                                    )
                                    .foregroundStyle(selectedRegion == region ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }

                Divider()

                if gamesByRound.isEmpty {
                    VStack(spacing: 8) {
                        Text("No games for \(selectedRegion.rawValue)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Try another region or wait for bracket data")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Graphical bracket view
                    ScrollView([.horizontal, .vertical], showsIndicators: true) {
                        HStack(alignment: .center, spacing: 0) {
                            ForEach(Array(gamesByRound.enumerated()), id: \.element.0) { roundIdx, roundData in
                                let (round, games) = roundData
                                VStack(spacing: 0) {
                                    Text(round.displayName)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .textCase(.uppercase)
                                        .padding(.bottom, 4)

                                    let spacing = spacingForRound(roundIdx: roundIdx)
                                    VStack(spacing: spacing) {
                                        ForEach(games) { game in
                                            GraphicalMatchupCell(event: game)
                                        }
                                    }
                                }
                                .frame(width: 155)

                                if roundIdx < gamesByRound.count - 1 {
                                    BracketConnectorView(
                                        fromCount: games.count,
                                        toCount: gamesByRound[roundIdx + 1].1.count,
                                        spacing: spacingForRound(roundIdx: roundIdx),
                                        cellHeight: 44
                                    )
                                    .frame(width: 20)
                                }
                            }
                        }
                        .padding(12)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.split.3x3")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Bracket loading...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Tournament data will appear as games are announced")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            if poller.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Button("Refresh") {
                    Task { await poller.fetchAllTournamentGames() }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func spacingForRound(roundIdx: Int) -> CGFloat {
        switch roundIdx {
        case 0: return 4
        case 1: return 52
        case 2: return 108
        case 3: return 220
        default: return 4
        }
    }
}

// MARK: - Graphical Matchup Cell

struct GraphicalMatchupCell: View {
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
            VStack(spacing: 0) {
                miniTeamRow(event.awayCompetitor, isTop: true, isWinner: isWinner(event.awayCompetitor))
                Divider()
                miniTeamRow(event.homeCompetitor, isTop: false, isWinner: isWinner(event.homeCompetitor))
            }
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(cellBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(event.isUpset ? Color.orange.opacity(0.5) : Color(nsColor: .separatorColor), lineWidth: event.isUpset ? 1 : 0.5)
            )
            .overlay(alignment: .leading) {
                VStack(spacing: 0) {
                    awayColor.frame(width: 2)
                    homeColor.frame(width: 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: 1))
            }
        }
        .buttonStyle(.plain)
    }

    private var cellBackground: Color {
        if event.isLive { return .red.opacity(0.06) }
        return Color(nsColor: .controlBackgroundColor)
    }

    private func miniTeamRow(_ competitor: Competitor?, isTop: Bool, isWinner: Bool) -> some View {
        HStack(spacing: 3) {
            if let seed = competitor?.seed {
                Text("\(seed)")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 12, alignment: .trailing)
            } else {
                Spacer().frame(width: 12)
            }

            if let url = competitor?.team.logoURL {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: .fit).frame(width: 12, height: 12)
                    } else {
                        Color.clear.frame(width: 12, height: 12)
                    }
                }
            }

            Text(competitor?.team.abbreviation ?? "TBD")
                .font(.system(size: 10, weight: isWinner ? .bold : .regular))
                .lineLimit(1)

            Spacer()

            if event.isLive {
                Circle().fill(.red).frame(width: 4, height: 4)
            }

            if let score = competitor?.score {
                Text(score)
                    .font(.system(size: 10, weight: isWinner ? .bold : .regular, design: .monospaced))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
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

// MARK: - Bracket Connector Lines

struct BracketConnectorView: View {
    let fromCount: Int
    let toCount: Int
    let spacing: CGFloat
    let cellHeight: CGFloat

    var body: some View {
        Canvas { context, size in
            let midX = size.width / 2
            let fromTotalHeight = CGFloat(fromCount) * cellHeight + CGFloat(max(fromCount - 1, 0)) * spacing
            let toTotalHeight = CGFloat(toCount) * cellHeight + CGFloat(max(toCount - 1, 0)) * (spacing * 2 + cellHeight)

            let startY = (size.height - fromTotalHeight) / 2
            let endY = (size.height - toTotalHeight) / 2

            for i in 0..<min(fromCount / 2, toCount) {
                let fromTop = startY + CGFloat(i * 2) * (cellHeight + spacing) + cellHeight / 2
                let fromBottom = startY + CGFloat(i * 2 + 1) * (cellHeight + spacing) + cellHeight / 2
                let toY = endY + CGFloat(i) * (cellHeight + spacing * 2 + cellHeight) + cellHeight / 2

                var path = Path()
                path.move(to: CGPoint(x: 0, y: fromTop))
                path.addLine(to: CGPoint(x: midX, y: fromTop))
                path.addLine(to: CGPoint(x: midX, y: fromBottom))
                path.addLine(to: CGPoint(x: 0, y: fromBottom))
                path.move(to: CGPoint(x: midX, y: (fromTop + fromBottom) / 2))
                path.addLine(to: CGPoint(x: size.width, y: toY))

                context.stroke(path, with: .color(.secondary.opacity(0.3)), lineWidth: 1)
            }
        }
        .frame(maxHeight: .infinity)
    }
}
