import Foundation

/// Build-time configuration and the endpoints of the outside services Hike talks to.
enum AppConfig {
    /// openrouteservice.org API key, set in Config/Secrets.xcconfig. Without it the planner
    /// falls back to Apple Maps walking directions, which carry no elevation.
    static var openRouteServiceKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "ORSAPIKey") as? String else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Topographic map tiles. OpenTopoMap is fine while developing; before publishing, switch
    /// to a tile provider whose terms cover an App Store app and offline downloads.
    static let outdoorTileTemplate = "https://tile.opentopomap.org/{z}/{x}/{y}.png"
    static let outdoorTileMaxZoom = 17
    static let outdoorTileAttribution = "© OpenStreetMap contributors, SRTM · © OpenTopoMap (CC-BY-SA)"

    /// Sent with every request so the services can identify the app.
    static let userAgent = "Hike-iOS/1.0"

    /// Zoom levels stored when a hike is saved for offline use.
    static let offlineZooms = 11...outdoorTileMaxZoom
    static let offlineTileLimit = 2500
}

enum MapLayer: String, CaseIterable, Identifiable {
    case outdoor
    case standard
    case satellite

    var id: String { rawValue }
}
