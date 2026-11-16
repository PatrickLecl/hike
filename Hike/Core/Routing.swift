import Foundation

/// A calculated walking route between waypoints.
struct PlannedRoute: Sendable {
    var points: [GeoPoint]
    /// Metres.
    var distance: Double
    var ascent: Double
    var descent: Double
    /// True when the points carry elevation data.
    var hasElevation: Bool

    /// Estimated walking time in seconds.
    var duration: TimeInterval {
        Geo.hikingDuration(distance: distance, ascent: ascent, descent: descent)
    }

    init(points: [GeoPoint]) {
        self.points = points
        distance = Geo.length(of: points)
        let gain = Geo.elevationGain(of: points)
        ascent = gain.ascent
        descent = gain.descent
        hasElevation = points.contains { $0.elevation != nil }
    }
}

enum RoutingError: Error, Equatable {
    case notEnoughWaypoints
    case noRouteFound
    case invalidResponse
    case server(String)
}

/// Request and response handling for openrouteservice.org (profile `foot-hiking`).
enum OpenRouteService {
    static let directionsURL = URL(string: "https://api.openrouteservice.org/v2/directions/foot-hiking/geojson")!
    static let elevationURL = URL(string: "https://api.openrouteservice.org/elevation/line")!
    /// The elevation endpoint accepts at most this many points per request.
    static let elevationPointLimit = 2000

    static func directionsBody(waypoints: [GeoPoint]) throws -> Data {
        guard waypoints.count >= 2 else { throw RoutingError.notEnoughWaypoints }
        let body: [String: Any] = [
            "coordinates": waypoints.map { [$0.longitude, $0.latitude] },
            "elevation": true,
            "instructions": false,
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    static func decodeDirections(_ data: Data) throws -> PlannedRoute {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RoutingError.invalidResponse
        }
        if let message = errorMessage(in: root) { throw RoutingError.server(message) }
        guard let features = root["features"] as? [[String: Any]],
              let geometry = features.first?["geometry"] as? [String: Any],
              let coordinates = geometry["coordinates"] as? [[Any]]
        else { throw RoutingError.invalidResponse }

        let points = Self.points(from: coordinates)
        guard points.count >= 2 else { throw RoutingError.noRouteFound }
        return PlannedRoute(points: points)
    }

    static func elevationBody(points: [GeoPoint]) throws -> Data {
        let body: [String: Any] = [
            "format_in": "polyline",
            "format_out": "polyline",
            "geometry": points.map { [$0.longitude, $0.latitude] },
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    static func decodeElevation(_ data: Data) throws -> [GeoPoint] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RoutingError.invalidResponse
        }
        if let message = errorMessage(in: root) { throw RoutingError.server(message) }
        guard let coordinates = root["geometry"] as? [[Any]] else { throw RoutingError.invalidResponse }
        return Self.points(from: coordinates)
    }

    /// Reads the human-readable message out of an error response, if it is one.
    static func errorMessage(in data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return errorMessage(in: root)
    }

    private static func errorMessage(in root: [String: Any]) -> String? {
        if let error = root["error"] as? [String: Any] {
            return (error["message"] as? String) ?? "Unknown error"
        }
        if let error = root["error"] as? String { return error }
        return nil
    }

    private static func points(from coordinates: [[Any]]) -> [GeoPoint] {
        coordinates.compactMap { coordinate in
            let numbers = coordinate.compactMap { ($0 as? NSNumber)?.doubleValue }
            guard numbers.count >= 2 else { return nil }
            let point = GeoPoint(
                latitude: numbers[1], longitude: numbers[0],
                elevation: numbers.count >= 3 ? numbers[2] : nil
            )
            return point.isValid ? point : nil
        }
    }
}
