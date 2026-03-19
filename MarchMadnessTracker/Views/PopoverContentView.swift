import SwiftUI

struct PopoverContentView: View {
    var poller: ScorePoller
    var onToggleToolbar: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    @State private var selectedTab: Tab = .scores
    @AppStorage("toolbarEnabled") private var toolbarEnabled = false

    enum Tab: String, CaseIterable {
        case scores = "Scores"
        case bracket = "Bracket"
        case schedule = "Schedule"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("🏀 March Madness")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                if poller.hasLiveGames {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text("LIVE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()

            // Content
            Group {
                switch selectedTab {
                case .scores:
                    ScoreboardView(poller: poller)
                case .bracket:
                    BracketView(poller: poller)
                case .schedule:
                    ScheduleView(poller: poller)
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            // Footer
            HStack(spacing: 10) {
                if let lastUpdated = poller.lastUpdated {
                    Text("Updated \(DateFormatters.lastUpdated.string(from: lastUpdated))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                // Toolbar toggle button
                Button {
                    onToggleToolbar?()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: toolbarEnabled ? "menubar.rectangle" : "menubar.arrow.up.rectangle")
                            .font(.caption)
                        Text(toolbarEnabled ? "Hide Ticker" : "Show Ticker")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(toolbarEnabled ? Color.accentColor : Color.primary)

                Button {
                    Task { await poller.refreshNow() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(poller.isLoading)

                Button {
                    onOpenSettings?()
                } label: {
                    Image(systemName: "gear")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Quit March Madness")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: Constants.popoverWidth, height: Constants.popoverHeight)
    }
}
