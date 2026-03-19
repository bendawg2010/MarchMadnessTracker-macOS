import SwiftUI

struct ScoreboardView: View {
    var poller: ScorePoller
    @State private var viewMode: ViewMode = .byStatus

    enum ViewMode: String, CaseIterable {
        case byStatus = "Status"
        case byRound = "Round"
        case byDate = "Date"
    }

    var body: some View {
        if poller.isLoading && poller.games.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading all tournament games...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = poller.errorMessage, poller.games.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await poller.refreshNow() }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else if poller.games.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "sportscourt")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No tournament games found")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                // View mode picker
                HStack {
                    Picker("Group by", selection: $viewMode) {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)

                    Spacer()

                    Text("\(poller.games.count) games")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 2) {
                        switch viewMode {
                        case .byStatus:
                            statusView
                        case .byRound:
                            roundView
                        case .byDate:
                            dateView
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - By Status

    @ViewBuilder
    private var statusView: some View {
        if !poller.liveGames.isEmpty {
            sectionHeader("In Progress (\(poller.liveGames.count))")
            ForEach(poller.liveGames) { game in
                GameRowView(event: game)
            }
        }

        if !poller.scheduledGames.isEmpty {
            sectionHeader("Upcoming (\(poller.scheduledGames.count))")
            ForEach(poller.scheduledGames) { game in
                GameRowView(event: game)
            }
        }

        if !poller.completedGames.isEmpty {
            sectionHeader("Completed (\(poller.completedGames.count))")
            ForEach(poller.completedGames) { game in
                GameRowView(event: game)
            }
        }
    }

    // MARK: - By Round

    @ViewBuilder
    private var roundView: some View {
        ForEach(poller.gamesByRound, id: \.0) { roundName, games in
            sectionHeader("\(roundName) (\(games.count))")
            ForEach(games) { game in
                GameRowView(event: game)
            }
        }
    }

    // MARK: - By Date

    @ViewBuilder
    private var dateView: some View {
        ForEach(poller.gamesByDate, id: \.0) { dateString, games in
            sectionHeader("\(dateString) (\(games.count))")
            ForEach(games) { game in
                GameRowView(event: game)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
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
