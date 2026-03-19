import SwiftUI

struct SettingsView: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("closeGameThreshold") private var closeGameThreshold = 5
    @AppStorage("favoriteTeamId") private var favoriteTeamId = ""
    @AppStorage("favoriteTeamName") private var favoriteTeamName = ""
    @AppStorage("tickerSize") private var tickerSize: Double = 38

    var body: some View {
        Form {
            Section("Favorite Team") {
                HStack {
                    TextField("Team ID (from ESPN)", text: $favoriteTeamId)
                        .textFieldStyle(.roundedBorder)
                    TextField("Display Name", text: $favoriteTeamName)
                        .textFieldStyle(.roundedBorder)
                }
                Text("When set, your favorite team's score shows in the menu bar. Find team IDs at ESPN.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Ticker Bar") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Ticker Height")
                        Spacer()
                        Text("\(Int(tickerSize))pt")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $tickerSize, in: 28...64, step: 2)

                    HStack(spacing: 12) {
                        Button("Small") { tickerSize = 28 }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button("Default") { tickerSize = 38 }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button("Large") { tickerSize = 50 }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button("XL") { tickerSize = 64 }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                Text("Right-click a game in the ticker to detach it as a floating widget")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle("Close game alerts", isOn: $notificationsEnabled)
                if notificationsEnabled {
                    Stepper("Alert within \(closeGameThreshold) points", value: $closeGameThreshold, in: 1...15)
                    Toggle("Upset alerts (4+ seed difference)", isOn: .constant(notificationsEnabled))
                        .disabled(true)
                    Text("You'll be notified when a game is within \(closeGameThreshold) points in the final 5 minutes, and when major upsets happen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("About") {
                LabeledContent("App", value: "March Madness Tracker")
                LabeledContent("Version", value: "1.1")
                LabeledContent("Refresh Rate", value: "3 seconds (live)")
                Text("Live scores powered by ESPN. This app is not affiliated with ESPN or the NCAA.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Quit March Madness Tracker") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 500)
    }
}
