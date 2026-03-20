# March Madness Tracker - macOS

A native macOS menu bar app for tracking NCAA March Madness basketball scores in real-time.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue) ![Swift](https://img.shields.io/badge/Swift-6-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Menu Bar App** - Lives in your macOS menu bar with a basketball icon. Click to see all scores.
- **Live Scores** - Auto-refreshes every 3 seconds during live games, 20 seconds when idle.
- **Tournament Bracket** - Browse matchups organized by region and round.
- **Schedule** - See upcoming games with times and TV channels.
- **Watch Games** - Embedded browser for NCAA March Madness Live. Watch games right from the app with TV provider login.
- **Multiview** - Watch up to 4 games at once in a tiled grid. Auto-selects the most exciting games (closest scores, upsets, later rounds).
- **Desktop Widgets** - Official macOS WidgetKit widgets for your desktop/Notification Center:
  - **Live Score Widget** (Small/Medium/Large) - Shows current game scores
  - **Tournament Bracket Widget** (Medium/Large/Extra Large) - Visual bracket with connecting lines
- **Score Ticker** - Floating toolbar that scrolls live scores across the top of your screen.
- **Floating Score Widgets** - Detach individual games as always-on-top floating windows.
- **Notifications** - Get alerts for close games (within 5 points in final 5 minutes) and upsets.
- **Favorite Team** - Set your favorite team to see their score right in the menu bar.

## Installation

### Option 1: Build from Source (Recommended)

**Requirements:**
- macOS 14.0 (Sonoma) or later
- Xcode 15 or later
- Apple ID (free, for code signing)

**Steps:**
1. Clone this repository:
   ```bash
   git clone https://github.com/bendawg2010/MarchMadnessTracker-macOS.git
   cd MarchMadnessTracker-macOS
   ```
2. Open `MarchMadnessTracker.xcodeproj` in Xcode
3. In Xcode, go to **Signing & Capabilities** for both the main target and ScoreWidgetExtension target:
   - Select your Team (your Apple ID)
   - Xcode will automatically manage signing
4. Select the **MarchMadnessTracker** scheme (not ScoreWidgetExtension)
5. Click **Run** (or press Cmd+R)

**For Widgets to appear in Widget Gallery:**
- The app must be code-signed (step 3 above handles this)
- Run the app at least once
- Right-click your desktop > "Edit Widgets..." > Search "March Madness"

### Option 2: Download Release

Check the [Releases](https://github.com/bendawg2010/MarchMadnessTracker-macOS/releases) page for pre-built `.app` bundles.

## Usage

1. **Click the basketball icon** in your menu bar to open the popover
2. **Tabs**: Switch between Scores, Bracket, Schedule, and Watch
3. **Ticker**: Click "Show Ticker" in the popover footer to enable the floating score bar
4. **Widgets**: Right-click desktop > Edit Widgets > search "March Madness"
5. **Watch Games**: Go to the Watch tab and click any game to open it in a browser window
6. **Multiview**: When 2+ games are live, click "Multiview" to watch multiple games at once
7. **Settings**: Click the gear icon to set your favorite team, notification preferences, etc.

## Data Source

Uses ESPN's free public API (`site.api.espn.com`) - no API key or authentication required. Filters to NCAA Tournament games only using `groups=100`.

## Tech Stack

- **Swift 6 / SwiftUI** with AppKit bridging
- **WidgetKit** for desktop widgets
- **WebKit** for embedded game viewing
- **No third-party dependencies** - pure Apple frameworks

## Screenshots

*Coming soon*

## License

MIT License - feel free to use and modify.
