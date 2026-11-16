import Foundation

/// Geometry helpers for tracks and routes.
enum Geo {
    static let earthRadius = 6_371_008.8
    private static let mercatorRadius = 6_378_137.0

    /// Great-circle distance in metres (haversine).
    static func distance(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// Total length of a line in metres.
    static func length(of points: [GeoPoint]) -> Double {
        guard points.count > 1 else { return 0 }
        var total = 0.0
        for index in 1..<points.count {
            total += distance(points[index - 1], points[index])
        }
        return total
    }

    /// Distance from the start to every point, in metres. Same count as `points`.
    static func cumulativeDistances(of points: [GeoPoint]) -> [Double] {
        guard !points.isEmpty else { return [] }
        var result = [0.0]
        result.reserveCapacity(points.count)
        for index in points.indices.dropFirst() {
            result.append(result[index - 1] + distance(points[index - 1], points[index]))
        }
        return result
    }

    /// Total ascent and descent in metres. Changes smaller than `threshold` are treated as
    /// noise, which keeps GPS jitter from inflating the totals.
    static func elevationGain(of points: [GeoPoint], threshold: Double = 3) -> (ascent: Double, descent: Double) {
        var ascent = 0.0
        var descent = 0.0
        var reference: Double?
        for point in points {
            guard let elevation = point.elevation, elevation.isFinite else { continue }
            guard let current = reference else {
                reference = elevation
                continue
            }
            let delta = elevation - current
            if delta >= threshold {
                ascent += delta
                reference = elevation
            } else if delta <= -threshold {
                descent -= delta
                reference = elevation
            }
        }
        return (ascent, descent)
    }

    static func boundingBox(of points: [GeoPoint]) -> BoundingBox? {
        guard let first = points.first else { return nil }
        var box = BoundingBox(
            minLatitude: first.latitude, maxLatitude: first.latitude,
            minLongitude: first.longitude, maxLongitude: first.longitude
        )
        for point in points.dropFirst() {
            box.minLatitude = min(box.minLatitude, point.latitude)
            box.maxLatitude = max(box.maxLatitude, point.latitude)
            box.minLongitude = min(box.minLongitude, point.longitude)
            box.maxLongitude = max(box.maxLongitude, point.longitude)
        }
        return box
    }

    // MARK: Web Mercator (EPSG:3857)

    static func webMercator(from point: GeoPoint) -> (x: Double, y: Double) {
        let x = mercatorRadius * point.longitude * .pi / 180
        let clampedLatitude = max(min(point.latitude, 85.05112878), -85.05112878)
        let y = mercatorRadius * log(tan(.pi / 4 + clampedLatitude * .pi / 360))
        return (x, y)
    }

    static func point(fromWebMercatorX x: Double, y: Double) -> GeoPoint {
        let longitude = x / mercatorRadius * 180 / .pi
        let latitude = (2 * atan(exp(y / mercatorRadius)) - .pi / 2) * 180 / .pi
        return GeoPoint(latitude: latitude, longitude: longitude)
    }

    // MARK: Hiking time

    /// Estimated walking time in seconds, following DIN 33466: 4 km/h on the flat,
    /// 300 m/h climbing, 500 m/h descending; the smaller of the horizontal and vertical
    /// times counts for half.
    static func hikingDuration(distance: Double, ascent: Double, descent: Double) -> TimeInterval {
        let horizontal = distance / 4000 * 3600
        let vertical = (ascent / 300 + descent / 500) * 3600
        return max(horizontal, vertical) + min(horizontal, vertical) / 2
    }

    // MARK: Simplification

    /// Douglas–Peucker simplification. `tolerance` is in metres. Keeps first and last point.
    static func simplify(_ points: [GeoPoint], tolerance: Double) -> [GeoPoint] {
        guard points.count > 2, tolerance > 0 else { return points }
        let projected = points.map { webMercator(from: $0) }
        // Mercator stretches distances by 1 / cos(latitude); scale the tolerance to match.
        let scale = 1 / max(cos(points[points.count / 2].latitude * .pi / 180), 0.01)
        let limit = tolerance * scale

        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack: [(Int, Int)] = [(0, points.count - 1)]
        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            var maxDistance = 0.0
            var maxIndex = start
            for index in (start + 1)..<end {
                let d = perpendicularDistance(projected[index], projected[start], projected[end])
                if d > maxDistance {
                    maxDistance = d
                    maxIndex = index
                }
            }
            if maxDistance > limit {
                keep[maxIndex] = true
                stack.append((start, maxIndex))
                stack.append((maxIndex, end))
            }
        }
        return zip(points, keep).compactMap { $1 ? $0 : nil }
    }

    /// Reduces a line to at most `maxCount` points by keeping evenly spaced ones.
    static func downsample(_ points: [GeoPoint], maxCount: Int) -> [GeoPoint] {
        guard maxCount >= 2, points.count > maxCount else { return points }
        let step = Double(points.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { points[min(Int((Double($0) * step).rounded()), points.count - 1)] }
    }

    private static func perpendicularDistance(
        _ p: (x: Double, y: Double), _ a: (x: Double, y: Double), _ b: (x: Double, y: Double)
    ) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return ((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y)).squareRoot()
        }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        let projectionX = a.x + t * dx
        let projectionY = a.y + t * dy
        return ((p.x - projectionX) * (p.x - projectionX) + (p.y - projectionY) * (p.y - projectionY)).squareRoot()
    }
}

/// One sample of an elevation profile: distance from the start and height, both in metres.
struct ElevationSample: Hashable, Sendable, Identifiable {
    var distance: Double
    var elevation: Double
    var id: Double { distance }
}

enum ElevationProfile {
    /// Builds chart-ready samples from the points that carry an elevation.
    static func samples(for points: [GeoPoint], maxSamples: Int = 240) -> [ElevationSample] {
        let distances = Geo.cumulativeDistances(of: points)
        var all: [ElevationSample] = []
        all.reserveCapacity(points.count)
        for (index, point) in points.enumerated() {
            guard let elevation = point.elevation, elevation.isFinite else { continue }
            if let last = all.last, distances[index] <= last.distance { continue }
            all.append(ElevationSample(distance: distances[index], elevation: elevation))
        }
        guard maxSamples >= 2, all.count > maxSamples else { return all }
        let step = Double(all.count - 1) / Double(maxSamples - 1)
        return (0..<maxSamples).map { all[min(Int((Double($0) * step).rounded()), all.count - 1)] }
    }
}
