import SwiftUI

struct ScheduleView: View {
    var poller: ScorePoller

    private var upcomingGames: [Event] {
        let all = poller.allTournamentGames.isEmpty ? poller.games : poller.allTournamentGames
        return all
            .filter { $0.isScheduled }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    private var gamesByDate: [(String, [Event])] {
        let grouped = Dictionary(grouping: upcomingGames) { event -> String in
            guard let date = event.startDate else { return "TBD" }
            return DateFormatters.dayHeader.string(from: date)
        }
        return grouped.sorted { a, b in
            let dateA = a.value.first?.startDate ?? .distantFuture
            let dateB = b.value.first?.startDate ?? .distantFuture
            return dateA < dateB
        }
    }

    var body: some View {
        if upcomingGames.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No upcoming games scheduled")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(gamesByDate, id: \.0) { dateString, games in
                        HStack {
                            Text(dateString)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                        ForEach(games) { game in
                            ScheduleRowView(event: game)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }
}
