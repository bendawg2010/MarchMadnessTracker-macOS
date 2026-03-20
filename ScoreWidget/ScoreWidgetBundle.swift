import WidgetKit
import SwiftUI

@main
struct ScoreWidgetBundle: WidgetBundle {
    var body: some Widget {
        LiveScoreWidget()
        BracketWidget()
        PlayerStatsWidget()
    }
}
