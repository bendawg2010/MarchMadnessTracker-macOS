import Foundation
import Observation

@Observable
class ScorePoller {
    var todayGames: [Event] = []
    var allTournamentGames: [Event] = []
    var isLoading = false
    var lastUpdated: Date?
    var errorMessage: String?
    var allGamesLoaded = false

    private var timer: Timer?
    private let service = ESPNService()

    /// All unique tournament games — today's live data merged with historical data
    var games: [Event] {
        // Merge: prefer today's data (has live scores) over historical
        var merged: [String: Event] = [:]
        for game in allTournamentGames {
            merged[game.id] = game
        }
        // Today's games override with fresh data
        for game in todayGames {
            merged[game.id] = game
        }
        return Array(merged.values).sorted { a, b in
            (a.startDate ?? .distantFuture) < (b.startDate ?? .distantFuture)
        }
    }

    var liveGames: [Event] {
        games.filter { $0.isLive }
    }

    var completedGames: [Event] {
        games.filter { $0.isFinal }
    }

    var scheduledGames: [Event] {
        games.filter { $0.isScheduled }
    }

    var hasLiveGames: Bool {
        !liveGames.isEmpty
    }

    var currentPollingInterval: TimeInterval {
        hasLiveGames ? Constants.livePollingInterval : Constants.idlePollingInterval
    }

    /// Games grouped by round name for display
    var gamesByRound: [(String, [Event])] {
        let grouped = Dictionary(grouping: games) { event -> String in
            event.roundName ?? "Tournament"
        }
        // Order rounds logically
        let roundOrder = ["First Four", "1st Round", "2nd Round", "Sweet 16", "Elite 8", "Final Four", "National Championship"]
        return grouped.sorted { a, b in
            let idxA = roundOrder.firstIndex(where: { a.key.localizedCaseInsensitiveContains($0) }) ?? 99
            let idxB = roundOrder.firstIndex(where: { b.key.localizedCaseInsensitiveContains($0) }) ?? 99
            return idxA < idxB
        }
    }

    /// Games grouped by date for display
    var gamesByDate: [(String, [Event])] {
        let grouped = Dictionary(grouping: games) { event -> String in
            guard let date = event.startDate else { return "TBD" }
            return DateFormatters.dayHeader.string(from: date)
        }
        return grouped.sorted { a, b in
            let dateA = a.value.first?.startDate ?? .distantFuture
            let dateB = b.value.first?.startDate ?? .distantFuture
            return dateA < dateB
        }
    }

    /// Only games that have real teams assigned (not future TBD bracket slots)
    private func hasRealTeams(_ event: Event) -> Bool {
        guard let comp = event.competition else { return false }
        // Must have at least 2 competitors with non-empty team names
        let realTeams = comp.competitors.filter { !$0.team.abbreviation.isEmpty && $0.team.abbreviation != "TBD" }
        return realTeams.count >= 2
    }

    /// Games for the toolbar ticker — prioritizes live & close games, then today's results
    var tickerGames: [Event] {
        let calendar = Calendar.current
        let now = Date()

        // 1. Live games (always show, sorted by closeness)
        let live = liveGames.filter { hasRealTeams($0) }.sorted { a, b in
            (a.scoreDifference ?? 999) < (b.scoreDifference ?? 999)
        }

        // 2. Today's completed games (most recent first)
        let todayFinals = completedGames.filter { event in
            hasRealTeams(event) && {
                guard let date = event.startDate else { return false }
                return calendar.isDateInToday(date)
            }()
        }.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }

        // 3. Today's upcoming games with real teams
        let todayUpcoming = scheduledGames.filter { event in
            hasRealTeams(event) && {
                guard let date = event.startDate else { return false }
                return calendar.isDateInToday(date) && date > now
            }()
        }.sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }

        // 4. Yesterday's close/notable finals as fallback
        let yesterdayFinals = completedGames.filter { event in
            hasRealTeams(event) && {
                guard let date = event.startDate else { return false }
                return calendar.isDateInYesterday(date)
            }()
        }.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }

        let result = live + todayFinals + todayUpcoming
        if result.isEmpty {
            // Fallback: show yesterday or most recent games with real teams
            let fallback = (yesterdayFinals + completedGames.filter { hasRealTeams($0) }.suffix(8))
            var seen = Set<String>()
            return fallback.filter { seen.insert($0.id).inserted }
        }
        return result
    }

    func startPolling() {
        Task {
            await refreshNow()
            await fetchAllTournamentGames()
        }
        scheduleTimer()
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refreshNow() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await service.fetchScoreboard(tournamentOnly: true)
            await MainActor.run {
                self.todayGames = response.events
                self.lastUpdated = Date()
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func fetchAllTournamentGames() async {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let startComponents = DateComponents(year: year, month: 3, day: 17)
        let endComponents = DateComponents(year: year, month: 4, day: 8)

        guard let startDate = calendar.date(from: startComponents),
              let endDate = calendar.date(from: endComponents) else { return }

        do {
            let events = try await service.fetchTournamentGames(from: startDate, to: endDate)
            await MainActor.run {
                self.allTournamentGames = events
                self.allGamesLoaded = true
            }
        } catch {
            // Supplementary data; don't show error
        }
    }

    func gameForTeam(teamId: String) -> Event? {
        if let live = liveGames.first(where: { containsTeam($0, teamId: teamId) }) {
            return live
        }
        if let scheduled = scheduledGames.first(where: { containsTeam($0, teamId: teamId) }) {
            return scheduled
        }
        return completedGames.last(where: { containsTeam($0, teamId: teamId) })
    }

    private func containsTeam(_ event: Event, teamId: String) -> Bool {
        event.competition?.competitors.contains { $0.team.id == teamId } ?? false
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = currentPollingInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.refreshNow()
                await MainActor.run {
                    self.scheduleTimer()
                }
            }
        }
    }
}
