import Foundation

enum Constants {
    static let espnBaseURL = "https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball"
    static let scoreboardEndpoint = "\(espnBaseURL)/scoreboard"
    static let tournamentGroupID = "100" // NCAA Tournament filter

    static let livePollingInterval: TimeInterval = 3
    static let idlePollingInterval: TimeInterval = 20

    static let popoverWidth: CGFloat = 420
    static let popoverHeight: CGFloat = 580

    static let closeGamePointThreshold = 5
    static let closeGameTimeThreshold: Double = 300 // 5 minutes in seconds

    static let toolbarHeight: CGFloat = 38
}

// MARK: - Notification Names

extension Notification.Name {
    static let openGameDetail = Notification.Name("openGameDetail")
    static let createGameWidget = Notification.Name("createGameWidget")
}
