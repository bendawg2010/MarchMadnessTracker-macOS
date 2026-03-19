import SwiftUI

struct BracketRegionView: View {
    let region: TournamentRegion
    let games: [Event]

    private var gamesByRound: [(TournamentRound, [Event])] {
        let grouped = Dictionary(grouping: games) { event -> TournamentRound in
            guard let roundName = event.roundName else { return .firstRound }
            return TournamentRound.fromString(roundName) ?? .firstRound
        }
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(gamesByRound, id: \.0) { round, roundGames in
                Section {
                    ForEach(roundGames) { game in
                        BracketMatchupView(event: game)
                    }
                } header: {
                    HStack {
                        Text(round.displayName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                }
            }
        }
    }
}
