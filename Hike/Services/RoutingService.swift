import CoreLocation
import Foundation
import MapKit

extension GeoPoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

/// Shared helper for the JSON services.
enum Network {
    static func data(for request: URLRequest) async throws -> (Data, Int) {
        var request = request
        request.setValue(AppConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// Turns planner waypoints into a walkable route.
///
/// With an openrouteservice key the route follows hiking paths and includes elevation.
/// Without one, Apple Maps walking directions are used leg by leg.
actor RoutingService {
    private struct Leg: Hashable {
        var from: GeoPoint
        var to: GeoPoint
    }

    private var appleLegCache: [Leg: [GeoPoint]] = [:]

    func route(through waypoints: [GeoPoint]) async throws -> PlannedRoute {
        guard waypoints.count >= 2 else { throw RoutingError.notEnoughWaypoints }
        if let key = AppConfig.openRouteServiceKey {
            return try await openRouteServiceRoute(through: waypoints, key: key)
        }
        return try await appleRoute(through: waypoints)
    }

    private func openRouteServiceRoute(through waypoints: [GeoPoint], key: String) async throws -> PlannedRoute {
        var request = URLRequest(url: OpenRouteService.directionsURL)
        request.httpMethod = "POST"
        request.httpBody = try OpenRouteService.directionsBody(waypoints: waypoints)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "Authorization")
        let (data, status) = try await Network.data(for: request)
        if status == 404 { throw RoutingError.noRouteFound }
        return try OpenRouteService.decodeDirections(data)
    }

    private func appleRoute(through waypoints: [GeoPoint]) async throws -> PlannedRoute {
        var points: [GeoPoint] = []
        for index in 1..<waypoints.count {
            let leg = Leg(from: waypoints[index - 1], to: waypoints[index])
            let legPoints: [GeoPoint]
            if let cached = appleLegCache[leg] {
                legPoints = cached
            } else {
                legPoints = try await appleLeg(from: leg.from, to: leg.to)
                appleLegCache[leg] = legPoints
            }
            points.append(contentsOf: points.isEmpty ? legPoints : Array(legPoints.dropFirst()))
        }
        guard points.count >= 2 else { throw RoutingError.noRouteFound }
        return PlannedRoute(points: points)
    }

    private func appleLeg(from start: GeoPoint, to end: GeoPoint) async throws -> [GeoPoint] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end.coordinate))
        request.transportType = .walking
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let polyline = response.routes.first?.polyline, polyline.pointCount >= 2 else {
                throw RoutingError.noRouteFound
            }
            var coordinates = [CLLocationCoordinate2D](
                repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount
            )
            polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: polyline.pointCount))
            return coordinates.map { GeoPoint($0) }
        } catch let error as RoutingError {
            throw error
        } catch {
            throw RoutingError.noRouteFound
        }
    }
}

/// Looks up elevation for lines that come without it (waymarked trails, some GPX files).
/// Needs an openrouteservice key; returns nil when unavailable.
enum ElevationService {
    static var isAvailable: Bool { AppConfig.openRouteServiceKey != nil }

    static func elevations(for points: [GeoPoint]) async -> [GeoPoint]? {
        guard let key = AppConfig.openRouteServiceKey, points.count >= 2 else { return nil }
        let sampled = Geo.downsample(points, maxCount: OpenRouteService.elevationPointLimit)
        do {
            var request = URLRequest(url: OpenRouteService.elevationURL)
            request.httpMethod = "POST"
            request.httpBody = try OpenRouteService.elevationBody(points: sampled)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(key, forHTTPHeaderField: "Authorization")
            let (data, _) = try await Network.data(for: request)
            let result = try OpenRouteService.decodeElevation(data)
            return result.contains { $0.elevation != nil } ? result : nil
        } catch {
            return nil
        }
    }
}

/// Finds waymarked hiking trails.
enum TrailService {
    static func search(_ query: String) async throws -> [TrailSummary] {
        guard let url = WaymarkedTrails.searchURL(query: query) else { throw TrailError.invalidResponse }
        return try WaymarkedTrails.decodeList(try await fetch(url))
    }

    static func trails(in box: BoundingBox) async throws -> [TrailSummary] {
        guard let url = WaymarkedTrails.areaURL(box: box) else { throw TrailError.invalidResponse }
        return try WaymarkedTrails.decodeList(try await fetch(url))
    }

    static func detail(for trail: TrailSummary) async throws -> TrailDetail {
        guard let url = WaymarkedTrails.detailURL(for: trail) else { throw TrailError.invalidResponse }
        let data = try await fetch(url)
        // Long trails are several megabytes of JSON; decode off the main thread.
        return try await Task.detached(priority: .userInitiated) {
            try WaymarkedTrails.decodeDetail(data)
        }.value
    }

    private static func fetch(_ url: URL) async throws -> Data {
        let (data, status) = try await Network.data(for: URLRequest(url: url))
        guard (200..<300).contains(status) else { throw TrailError.invalidResponse }
        return data
    }
}
