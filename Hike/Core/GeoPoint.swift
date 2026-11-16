import Foundation

/// A position on earth in WGS84, optionally with elevation (metres) and a timestamp.
/// Deliberately independent of CoreLocation so the core logic can be unit tested anywhere.
struct GeoPoint: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var elevation: Double?
    var time: Date?

    init(latitude: Double, longitude: Double, elevation: Double? = nil, time: Date? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.time = time
    }

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite
            && (-90.0...90.0).contains(latitude) && (-180.0...180.0).contains(longitude)
    }
}

/// A rectangular area in WGS84 degrees.
struct BoundingBox: Codable, Hashable, Sendable {
    var minLatitude: Double
    var maxLatitude: Double
    var minLongitude: Double
    var maxLongitude: Double

    var center: GeoPoint {
        GeoPoint(latitude: (minLatitude + maxLatitude) / 2, longitude: (minLongitude + maxLongitude) / 2)
    }

    var latitudeSpan: Double { maxLatitude - minLatitude }
    var longitudeSpan: Double { maxLongitude - minLongitude }

    /// Grows the box on every side by `fraction` of its size (with a small minimum so a
    /// single point still yields a usable area).
    func padded(by fraction: Double) -> BoundingBox {
        let latPad = max(latitudeSpan * fraction, 0.002)
        let lonPad = max(longitudeSpan * fraction, 0.002)
        return BoundingBox(
            minLatitude: max(minLatitude - latPad, -85),
            maxLatitude: min(maxLatitude + latPad, 85),
            minLongitude: max(minLongitude - lonPad, -180),
            maxLongitude: min(maxLongitude + lonPad, 180)
        )
    }
}
