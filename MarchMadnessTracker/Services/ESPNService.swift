import Foundation

actor ESPNService {
    private let session = URLSession.shared
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    func fetchScoreboard(date: Date? = nil, tournamentOnly: Bool = true) async throws -> ScoreboardResponse {
        var components = URLComponents(string: Constants.scoreboardEndpoint)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "100")
        ]

        if tournamentOnly {
            queryItems.append(URLQueryItem(name: "groups", value: Constants.tournamentGroupID))
        }

        if let date {
            queryItems.append(URLQueryItem(name: "dates", value: DateFormatters.espnDateParam.string(from: date)))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw ESPNError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ESPNError.requestFailed
        }

        return try decoder.decode(ScoreboardResponse.self, from: data)
    }

    func fetchTournamentGames(from startDate: Date, to endDate: Date) async throws -> [Event] {
        var allEvents: [Event] = []
        var current = startDate
        let calendar = Calendar.current

        while current <= endDate {
            do {
                let response = try await fetchScoreboard(date: current, tournamentOnly: true)
                allEvents.append(contentsOf: response.events)
            } catch {
                // Skip days that fail - some dates may have no games
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        // Deduplicate by event ID
        var seen = Set<String>()
        return allEvents.filter { seen.insert($0.id).inserted }
    }
}

enum ESPNError: LocalizedError {
    case invalidURL
    case requestFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .requestFailed: return "Failed to fetch data from ESPN"
        case .decodingFailed: return "Failed to parse ESPN response"
        }
    }
}
