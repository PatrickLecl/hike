# Hike

An iPhone app for planning hikes anywhere in Europe: draw a route on a topographic map,
discover waymarked trails, follow and record your hike with GPS, and take maps and routes
offline.

Built with SwiftUI, MapKit, SwiftData and Swift Charts. iOS 17 or later. Dutch and English.

## Open and run

1. Open `Hike.xcodeproj` in Xcode 16 or later.
2. Select the **Hike** target → **Signing & Capabilities** and choose your team.
3. Pick an iPhone or simulator and press Run.

The app works straight away. Without a routing key (see below) the planner uses Apple Maps
walking directions, which have no elevation data.

## Routing key (recommended)

For routes that follow hiking paths, with ascent, descent and an elevation profile:

1. Create a free account at [openrouteservice.org](https://openrouteservice.org) and copy
   your API key.
2. Create the file `Config/Secrets.xcconfig` (it is ignored by git) with one line:

   ```
   ORS_API_KEY = your-key-here
   ```

3. Build again. **Settings → Routing** in the app shows which engine is active.

## What is in the app

| Tab | What it does |
| --- | --- |
| **Plan** | Tap the map to add waypoints; the route, distance, ascent, walking time and elevation profile update as you go. Search for a place, undo, loop back to the start, save. |
| **Discover** | Waymarked trails (GR paths, E-paths, regional and local trails) for the area on the map or by name, with a detail page and "Save to My hikes". |
| **Record** | Follows your position, records the hike in the background and shows distance, time and ascent in large numbers. Can show a saved route to follow. |
| **My hikes** | Planned, recorded, imported and saved hikes. Import and share GPX, save the map for offline use, rename, delete. |

## Project layout

```
Hike/
  Core/       Pure Swift: geometry, GPX, tile maths, service response decoding
  Design/     The "Blaze" identity: colours, type, shared components, formatting
  Models/     SwiftData model and GPX import/export
  Services/   Routing, trails, location tracking, offline tile store
  Views/      The screens and the map
Config/       Info.plist additions and build configuration
Design/       Interface design boards and the app icon artwork
Tests/        Unit tests for Hike/Core
```

Everything inside `Hike/` is compiled into the app automatically (the project uses a
synchronised folder), so new files need no project changes.

## Tests

The core logic has no UIKit dependency and is tested through a Swift package:

```bash
swift test
```

## Design

The identity is called **Blaze**, after the painted waymarks along European trails: warm
map paper, spruce ink, one vermilion accent, serif headlines and contour lines as texture.
The colours and components live in `Hike/Design/`; the boards in `Design/` show the
intended look of the four main screens.

## Data sources and their terms

| Data | Source | Note |
| --- | --- | --- |
| Topographic map | [OpenTopoMap](https://opentopomap.org) | Fine for development. Before publishing, switch `AppConfig.outdoorTileTemplate` to a tile provider whose terms cover an App Store app and offline downloads. |
| Trails | [Waymarked Trails](https://hiking.waymarkedtrails.org) | OpenStreetMap data, ODbL. |
| Routing and elevation | [openrouteservice](https://openrouteservice.org) | Free plan has daily limits; the key is compiled into the app. For a public release, route requests through your own server so the key stays private. |

All map and trail data is © OpenStreetMap contributors.

## Before App Store submission

- Set your own bundle identifier (currently `com.patricklecl.hike`) and team.
- Choose a production map tile provider and move the routing key behind a server (see above).
- Add App Store screenshots, a privacy policy URL and the app description.
- Test recording on a real device: background location cannot be tested in the simulator.
