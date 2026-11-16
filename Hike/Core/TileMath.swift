import Foundation

/// A map tile in the standard XYZ ("slippy map") scheme.
struct TileCoordinate: Hashable, Sendable {
    var x: Int
    var y: Int
    var z: Int
}

enum TileMath {
    static func tile(latitude: Double, longitude: Double, zoom: Int) -> TileCoordinate {
        let n = Double(1 << zoom)
        let clampedLatitude = max(min(latitude, 85.05112878), -85.05112878)
        let latitudeRadians = clampedLatitude * .pi / 180
        let x = Int(((longitude + 180) / 360 * n).rounded(.down))
        let y = Int(((1 - log(tan(latitudeRadians) + 1 / cos(latitudeRadians)) / .pi) / 2 * n).rounded(.down))
        let maxIndex = Int(n) - 1
        return TileCoordinate(x: min(max(x, 0), maxIndex), y: min(max(y, 0), maxIndex), z: zoom)
    }

    /// Every tile needed to show a route at the given zoom levels, including `buffer` tiles
    /// around it so the surroundings are visible too.
    static func tiles(along points: [GeoPoint], zooms: ClosedRange<Int>, buffer: Int = 1) -> Set<TileCoordinate> {
        var result = Set<TileCoordinate>()
        for zoom in zooms {
            let maxIndex = (1 << zoom) - 1
            var previous: TileCoordinate?
            for point in points {
                let current = Self.tile(latitude: point.latitude, longitude: point.longitude, zoom: zoom)
                if current == previous { continue }
                // Fill the gap when two consecutive points are more than one tile apart.
                let steps = previous.map { max(abs($0.x - current.x), abs($0.y - current.y)) } ?? 1
                for step in 1...max(steps, 1) {
                    let fraction = Double(step) / Double(max(steps, 1))
                    let from = previous ?? current
                    let cx = from.x + Int((Double(current.x - from.x) * fraction).rounded())
                    let cy = from.y + Int((Double(current.y - from.y) * fraction).rounded())
                    for dx in -buffer...buffer {
                        for dy in -buffer...buffer {
                            let x = cx + dx
                            let y = cy + dy
                            guard x >= 0, y >= 0, x <= maxIndex, y <= maxIndex else { continue }
                            result.insert(TileCoordinate(x: x, y: y, z: zoom))
                        }
                    }
                }
                previous = current
            }
        }
        return result
    }

    /// Fills a `{z}/{x}/{y}` URL template. `{s}` picks one of the usual a/b/c subdomains.
    static func url(template: String, tile: TileCoordinate) -> URL? {
        let subdomains = ["a", "b", "c"]
        let filled = template
            .replacingOccurrences(of: "{z}", with: String(tile.z))
            .replacingOccurrences(of: "{x}", with: String(tile.x))
            .replacingOccurrences(of: "{y}", with: String(tile.y))
            .replacingOccurrences(of: "{s}", with: subdomains[abs(tile.x + tile.y) % subdomains.count])
        return URL(string: filled)
    }
}
