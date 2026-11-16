import Foundation

/// How far a waymarked trail reaches, as classified by OpenStreetMap.
enum TrailNetwork: String, CaseIterable, Codable, Sendable {
    case international = "INT"
    case national = "NAT"
    case regional = "REG"
    case local = "LOC"
}

/// A waymarked hiking trail as it appears in search results.
struct TrailSummary: Codable, Hashable, Identifiable, Sendable {
    var id: Int
    var type: String
    var name: String?
    var ref: String?
    var group: String?
    var itinerary: [String]?
    var symbolDescription: String?

    enum CodingKeys: String, CodingKey {
        case id, type, name, ref, group, itinerary
        case symbolDescription = "symbol_description"
    }

    init(
        id: Int, type: String = "relation", name: String? = nil, ref: String? = nil,
        group: String? = nil, itinerary: [String]? = nil, symbolDescription: String? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.ref = ref
        self.group = group
        self.itinerary = itinerary
        self.symbolDescription = symbolDescription
    }

    var network: TrailNetwork? { group.flatMap { TrailNetwork(rawValue: $0) } }

    /// The best available display name.
    var title: String {
        if let name, !name.isEmpty { return name }
        if let ref, !ref.isEmpty { return ref }
        return "#\(id)"
    }

    /// "Start – End" when the trail lists its itinerary.
    var itineraryText: String? {
        guard let itinerary, let first = itinerary.first, let last = itinerary.last, itinerary.count >= 2 else {
            return nil
        }
        return "\(first) – \(last)"
    }
}

/// A trail with its full geometry.
struct TrailDetail: Sendable {
    var summary: TrailSummary
    /// Length stated by the trail operator, in metres.
    var officialLength: Double?
    /// Length of the mapped geometry, in metres.
    var mappedLength: Double?
    var operatorName: String?
    var website: URL?
    var summaryText: String?
    /// Continuous pieces of the main route, in walking order.
    var segments: [[GeoPoint]]

    var allPoints: [GeoPoint] { segments.flatMap { $0 } }
    var length: Double { officialLength ?? mappedLength ?? Geo.length(of: allPoints) }
}

enum TrailError: Error {
    case invalidResponse
}

/// Request and response handling for the Waymarked Trails API (hiking.waymarkedtrails.org),
/// which serves the hiking routes mapped in OpenStreetMap.
enum WaymarkedTrails {
    static let baseURL = "https://hiking.waymarkedtrails.org/api/v1"

    static func searchURL(query: String, limit: Int = 30) -> URL? {
        var components = URLComponents(string: baseURL + "/list/search")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return components?.url
    }

    /// Trails crossing the given area. The API expects the box in Web Mercator metres.
    static func areaURL(box: BoundingBox, limit: Int = 40) -> URL? {
        let southWest = Geo.webMercator(from: GeoPoint(latitude: box.minLatitude, longitude: box.minLongitude))
        let northEast = Geo.webMercator(from: GeoPoint(latitude: box.maxLatitude, longitude: box.maxLongitude))
        let values = [southWest.x, southWest.y, northEast.x, northEast.y]
            .map { String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), $0) }
            .joined(separator: ",")
        var components = URLComponents(string: baseURL + "/list/by_area")
        components?.queryItems = [
            URLQueryItem(name: "bbox", value: values),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return components?.url
    }

    static func detailURL(for trail: TrailSummary) -> URL? {
        URL(string: baseURL + "/details/\(trail.type)/\(trail.id)")
    }

    static func decodeList(_ data: Data) throws -> [TrailSummary] {
        struct Response: Decodable { var results: [TrailSummary] }
        do {
            return try JSONDecoder().decode(Response.self, from: data).results
        } catch {
            throw TrailError.invalidResponse
        }
    }

    static func decodeDetail(_ data: Data) throws -> TrailDetail {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = (root["id"] as? NSNumber)?.intValue
        else { throw TrailError.invalidResponse }

        let summary = TrailSummary(
            id: id,
            type: root["type"] as? String ?? "relation",
            name: root["name"] as? String,
            ref: root["ref"] as? String,
            group: root["group"] as? String,
            itinerary: root["itinerary"] as? [String],
            symbolDescription: root["symbol_description"] as? String
        )
        let route = root["route"] as? [String: Any]
        var ways: [[GeoPoint]] = []
        if let route { collectWays(in: route, into: &ways) }

        return TrailDetail(
            summary: summary,
            officialLength: (root["official_length"] as? NSNumber)?.doubleValue,
            mappedLength: (route?["length"] as? NSNumber)?.doubleValue,
            operatorName: root["operator"] as? String,
            website: (root["url"] as? String).flatMap { URL(string: $0) },
            summaryText: root["description"] as? String,
            segments: stitch(ways)
        )
    }

    /// Walks the nested route structure in order and gathers the geometry of every way on
    /// the main line. Where a trail splits by direction, the forward branch is followed.
    private static func collectWays(in node: [String: Any], into ways: inout [[GeoPoint]]) {
        if let geometry = node["geometry"] as? [String: Any],
           let coordinates = geometry["coordinates"] as? [[Any]] {
            let points: [GeoPoint] = coordinates.compactMap { coordinate in
                let numbers = coordinate.compactMap { ($0 as? NSNumber)?.doubleValue }
                guard numbers.count >= 2 else { return nil }
                let point = Geo.point(fromWebMercatorX: numbers[0], y: numbers[1])
                return point.isValid ? point : nil
            }
            if points.count >= 2 { ways.append(points) }
            return
        }
        for key in ["main", "ways", "forward"] {
            guard let children = node[key] as? [[String: Any]] else { continue }
            for child in children { collectWays(in: child, into: &ways) }
        }
    }

    /// Joins consecutive ways that touch end to start into continuous segments.
    static func stitch(_ ways: [[GeoPoint]], tolerance: Double = 5) -> [[GeoPoint]] {
        var segments: [[GeoPoint]] = []
        for way in ways where !way.isEmpty {
            guard let lastPoint = segments.last?.last else {
                segments.append(way)
                continue
            }
            if Geo.distance(lastPoint, way[0]) <= tolerance {
                segments[segments.count - 1].append(contentsOf: way.dropFirst())
            } else if Geo.distance(lastPoint, way[way.count - 1]) <= tolerance {
                segments[segments.count - 1].append(contentsOf: way.reversed().dropFirst())
            } else {
                segments.append(way)
            }
        }
        return segments
    }
}
