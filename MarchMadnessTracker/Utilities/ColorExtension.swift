import SwiftUI
import AppKit

extension Color {
    /// Create a Color from a hex string (without #), as provided by ESPN API
    init?(hex: String?) {
        guard let hex, !hex.isEmpty else { return nil }
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard clean.count == 6 else { return nil }

        var rgbValue: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&rgbValue)

        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

extension Event {
    /// Whether a lower-seeded team is currently winning or won (upset)
    var isUpset: Bool {
        guard let away = awayCompetitor, let home = homeCompetitor else { return false }
        guard let awaySeed = away.seed, let homeSeed = home.seed else { return false }
        guard let awayScore = away.scoreInt, let homeScore = home.scoreInt else { return false }

        if awaySeed > homeSeed && awayScore > homeScore { return true }
        if homeSeed > awaySeed && homeScore > awayScore { return true }
        return false
    }

    /// The seed difference if an upset is happening (higher = bigger upset)
    var upsetMagnitude: Int? {
        guard isUpset else { return nil }
        guard let away = awayCompetitor, let home = homeCompetitor else { return nil }
        guard let awaySeed = away.seed, let homeSeed = home.seed else { return nil }
        return abs(awaySeed - homeSeed)
    }

    /// The underdog competitor (higher seed number)
    var underdog: Competitor? {
        guard let away = awayCompetitor, let home = homeCompetitor else { return nil }
        guard let awaySeed = away.seed, let homeSeed = home.seed else { return nil }
        return awaySeed > homeSeed ? away : home
    }

    /// The favorite competitor (lower seed number)
    var favorite: Competitor? {
        guard let away = awayCompetitor, let home = homeCompetitor else { return nil }
        guard let awaySeed = away.seed, let homeSeed = home.seed else { return nil }
        return awaySeed < homeSeed ? away : home
    }
}
