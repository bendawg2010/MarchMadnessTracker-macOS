import Foundation

// MARK: - ESPN Scoreboard API Response

struct ScoreboardResponse: Codable {
    let events: [Event]
}

struct Event: Codable, Identifiable {
    let id: String
    let date: String
    let name: String
    let shortName: String
    let competitions: [Competition]
    let status: GameStatus
    let notes: [Note]?

    var competition: Competition? { competitions.first }

    var homeCompetitor: Competitor? {
        competition?.competitors.first { $0.homeAway == "home" }
    }

    var awayCompetitor: Competitor? {
        competition?.competitors.first { $0.homeAway == "away" }
    }

    var scoreDifference: Int? {
        guard let home = homeCompetitor?.scoreInt,
              let away = awayCompetitor?.scoreInt else { return nil }
        return abs(home - away)
    }

    var isLive: Bool {
        status.type.state == "in"
    }

    var isFinal: Bool {
        status.type.state == "post"
    }

    var isScheduled: Bool {
        status.type.state == "pre"
    }

    var startDate: Date? {
        DateFormatters.espnISO.date(from: date)
    }

    var regionName: String? {
        guard let headline = notes?.first?.headline else { return nil }
        let parts = headline.components(separatedBy: " - ")
        guard parts.count >= 2 else { return nil }
        return parts[parts.count - 2].trimmingCharacters(in: .whitespaces)
    }

    var roundName: String? {
        guard let headline = notes?.first?.headline else { return nil }
        let parts = headline.components(separatedBy: " - ")
        return parts.last?.trimmingCharacters(in: .whitespaces)
    }
}

struct Competition: Codable {
    let id: String
    let competitors: [Competitor]
    let venue: Venue?
    let broadcasts: [Broadcast]?
}

struct Competitor: Codable {
    let id: String
    let homeAway: String
    let team: TeamInfo
    let score: String?
    let curatedRank: CuratedRank?
    let records: [TeamRecord]?

    var scoreInt: Int? {
        guard let score else { return nil }
        return Int(score)
    }

    var seed: Int? {
        curatedRank?.current
    }
}

struct TeamInfo: Codable, Identifiable {
    let id: String
    let location: String
    let name: String
    let abbreviation: String
    let displayName: String
    let color: String?
    let alternateColor: String?
    let logo: String?

    var logoURL: URL? {
        guard let logo else { return nil }
        return URL(string: logo)
    }
}

struct CuratedRank: Codable {
    let current: Int?
}

struct TeamRecord: Codable {
    let summary: String?
    let type: String?
}

struct GameStatus: Codable {
    let clock: Double?
    let displayClock: String?
    let period: Int
    let type: StatusType
}

struct StatusType: Codable {
    let id: String
    let name: String
    let state: String
    let completed: Bool
    let detail: String?
    let shortDetail: String?
}

struct Note: Codable {
    let headline: String?
}

struct Venue: Codable {
    let fullName: String?
    let city: String?
    let state: String?
}

struct Broadcast: Codable {
    let names: [String]?
}
