import Foundation

enum TournamentRound: Int, CaseIterable, Comparable {
    case firstFour = 0
    case firstRound = 1
    case secondRound = 2
    case sweet16 = 3
    case elite8 = 4
    case finalFour = 5
    case championship = 6

    var displayName: String {
        switch self {
        case .firstFour: return "First Four"
        case .firstRound: return "1st Round"
        case .secondRound: return "2nd Round"
        case .sweet16: return "Sweet 16"
        case .elite8: return "Elite 8"
        case .finalFour: return "Final Four"
        case .championship: return "Championship"
        }
    }

    static func < (lhs: TournamentRound, rhs: TournamentRound) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func fromString(_ str: String) -> TournamentRound? {
        let lower = str.lowercased()
        if lower.contains("first four") { return .firstFour }
        if lower.contains("1st round") || lower.contains("first round") { return .firstRound }
        if lower.contains("2nd round") || lower.contains("second round") { return .secondRound }
        if lower.contains("sweet 16") || lower.contains("sweet sixteen") { return .sweet16 }
        if lower.contains("elite 8") || lower.contains("elite eight") { return .elite8 }
        if lower.contains("final four") || lower.contains("semifinal") { return .finalFour }
        if lower.contains("championship") || lower.contains("national championship") || lower.contains("final") && !lower.contains("four") { return .championship }
        return nil
    }
}

enum TournamentRegion: String, CaseIterable, Identifiable {
    case south = "South"
    case east = "East"
    case midwest = "Midwest"
    case west = "West"
    case finalFour = "Final Four"

    var id: String { rawValue }

    static func fromString(_ str: String) -> TournamentRegion? {
        let lower = str.lowercased()
        if lower.contains("south") { return .south }
        if lower.contains("east") && !lower.contains("midwest") { return .east }
        if lower.contains("midwest") { return .midwest }
        if lower.contains("west") && !lower.contains("midwest") { return .west }
        return nil
    }
}

struct BracketMatchup: Identifiable {
    let id: String
    let round: TournamentRound
    let region: TournamentRegion?
    let event: Event

    var topTeam: BracketTeam? {
        guard let competitor = event.awayCompetitor else { return nil }
        return BracketTeam(from: competitor)
    }

    var bottomTeam: BracketTeam? {
        guard let competitor = event.homeCompetitor else { return nil }
        return BracketTeam(from: competitor)
    }

    var isComplete: Bool { event.isFinal }
    var isLive: Bool { event.isLive }
}

struct BracketTeam {
    let seed: Int?
    let name: String
    let abbreviation: String
    let score: Int?
    let logoURL: URL?
    let color: String?
    let isWinner: Bool

    init(from competitor: Competitor) {
        self.seed = competitor.seed
        self.name = competitor.team.displayName
        self.abbreviation = competitor.team.abbreviation
        self.score = competitor.scoreInt
        self.logoURL = competitor.team.logoURL
        self.color = competitor.team.color
        self.isWinner = false // computed later based on context
    }
}
