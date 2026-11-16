import Foundation
import SwiftData

enum HikeKind: String, Codable, CaseIterable {
    /// Drawn in the planner.
    case planned
    /// Recorded with GPS while walking.
    case recorded
    /// Imported from a GPX file.
    case imported
    /// Saved from a waymarked trail.
    case trail
}

/// A hike kept in "My hikes". Stored on the device with SwiftData.
@Model
final class SavedHike {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var kindRaw: String = HikeKind.planned.rawValue
    /// Metres.
    var distance: Double = 0
    var ascent: Double = 0
    var descent: Double = 0
    /// Seconds: the time walked for recordings, an estimate otherwise.
    var duration: Double = 0
    var hasElevation: Bool = false
    var isOffline: Bool = false
    /// JSON-encoded `[GeoPoint]` of the full line.
    @Attribute(.externalStorage) var trackData: Data = Data()
    /// JSON-encoded `[GeoPoint]` of the planner waypoints, if any.
    var waypointData: Data = Data()
    /// JSON-encoded, heavily simplified line for list thumbnails.
    var previewData: Data = Data()

    init(name: String, kind: HikeKind, points: [GeoPoint], waypoints: [GeoPoint] = [], walkedDuration: TimeInterval? = nil) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.kindRaw = kind.rawValue

        let gain = Geo.elevationGain(of: points, threshold: kind == .recorded ? 5 : 3)
        let length = Geo.length(of: points)
        self.distance = length
        self.ascent = gain.ascent
        self.descent = gain.descent
        self.hasElevation = points.contains { $0.elevation != nil }
        self.duration = walkedDuration
            ?? Geo.hikingDuration(distance: length, ascent: gain.ascent, descent: gain.descent)

        let encoder = JSONEncoder()
        self.trackData = (try? encoder.encode(points)) ?? Data()
        self.waypointData = (try? encoder.encode(waypoints)) ?? Data()
        let preview = Geo.downsample(Geo.simplify(points, tolerance: max(length / 400, 5)), maxCount: 120)
            .map { GeoPoint(latitude: $0.latitude, longitude: $0.longitude) }
        self.previewData = (try? encoder.encode(preview)) ?? Data()
    }

    var kind: HikeKind { HikeKind(rawValue: kindRaw) ?? .planned }

    /// Decodes the full line. Not cheap for long hikes: read it once and keep the result.
    var points: [GeoPoint] {
        (try? JSONDecoder().decode([GeoPoint].self, from: trackData)) ?? []
    }

    var waypoints: [GeoPoint] {
        (try? JSONDecoder().decode([GeoPoint].self, from: waypointData)) ?? []
    }

    var previewPoints: [GeoPoint] {
        (try? JSONDecoder().decode([GeoPoint].self, from: previewData)) ?? []
    }

    /// Replaces the line, e.g. after elevation data has been added, and updates the totals.
    func updatePoints(_ points: [GeoPoint]) {
        let gain = Geo.elevationGain(of: points, threshold: kind == .recorded ? 5 : 3)
        ascent = gain.ascent
        descent = gain.descent
        hasElevation = points.contains { $0.elevation != nil }
        if kind != .recorded {
            duration = Geo.hikingDuration(distance: distance, ascent: gain.ascent, descent: gain.descent)
        }
        trackData = (try? JSONEncoder().encode(points)) ?? trackData
    }
}

enum HikeImporter {
    /// Parses a GPX file and stores it as a hike. Returns the new hike.
    @discardableResult
    static func importGPX(_ data: Data, fallbackName: String, into context: ModelContext) throws -> SavedHike {
        let document = try GPXParser.parse(data)
        let points = document.allPoints
        guard points.count >= 2 else { throw GPXError.empty }
        let hike = SavedHike(
            name: document.name ?? fallbackName,
            kind: .imported,
            points: points,
            waypoints: document.waypoints.map(\.point)
        )
        context.insert(hike)
        return hike
    }

    /// Writes the hike to a temporary GPX file for sharing.
    static func exportGPX(_ hike: SavedHike) -> URL? {
        let waypoints = hike.waypoints.enumerated().map { index, point in
            GPXWaypoint(name: String(index + 1), point: point)
        }
        let xml = GPXWriter.string(name: hike.name, points: hike.points, waypoints: waypoints)
        let safeName = hike.name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName.isEmpty ? "hike" : safeName)
            .appendingPathExtension("gpx")
        do {
            try xml.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
