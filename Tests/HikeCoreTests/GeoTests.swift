import XCTest
@testable import HikeCore

final class GeoTests: XCTestCase {
    private let amsterdam = GeoPoint(latitude: 52.3676, longitude: 4.9041)
    private let brussels = GeoPoint(latitude: 50.8503, longitude: 4.3517)

    func testDistanceBetweenCities() {
        XCTAssertEqual(Geo.distance(amsterdam, brussels), 172_973.4, accuracy: 1)
        XCTAssertEqual(Geo.distance(amsterdam, amsterdam), 0, accuracy: 0.001)
    }

    func testOneDegreeOfLatitude() {
        let a = GeoPoint(latitude: 50, longitude: 10)
        let b = GeoPoint(latitude: 51, longitude: 10)
        XCTAssertEqual(Geo.distance(a, b), 111_195.1, accuracy: 1)
    }

    func testLengthAndCumulativeDistances() {
        let line = [
            GeoPoint(latitude: 50, longitude: 10),
            GeoPoint(latitude: 50.5, longitude: 10),
            GeoPoint(latitude: 51, longitude: 10),
        ]
        XCTAssertEqual(Geo.length(of: line), 111_195.1, accuracy: 1)
        let cumulative = Geo.cumulativeDistances(of: line)
        XCTAssertEqual(cumulative.count, 3)
        XCTAssertEqual(cumulative[0], 0)
        XCTAssertEqual(cumulative[2], Geo.length(of: line), accuracy: 0.001)
        XCTAssertEqual(Geo.length(of: []), 0)
        XCTAssertEqual(Geo.length(of: [amsterdam]), 0)
    }

    func testElevationGainIgnoresNoise() {
        let elevations: [Double] = [100, 101, 99, 100, 150, 149, 151, 120, 121, 200]
        let points = elevations.map { GeoPoint(latitude: 50, longitude: 10, elevation: $0) }
        let gain = Geo.elevationGain(of: points, threshold: 3)
        // 100 → 150 (+50), 150 → 120 (−30), 120 → 200 (+80)
        XCTAssertEqual(gain.ascent, 130, accuracy: 0.001)
        XCTAssertEqual(gain.descent, 30, accuracy: 0.001)
    }

    func testElevationGainWithoutElevation() {
        let gain = Geo.elevationGain(of: [amsterdam, brussels])
        XCTAssertEqual(gain.ascent, 0)
        XCTAssertEqual(gain.descent, 0)
    }

    func testBoundingBox() throws {
        let box = try XCTUnwrap(Geo.boundingBox(of: [amsterdam, brussels]))
        XCTAssertEqual(box.minLatitude, 50.8503)
        XCTAssertEqual(box.maxLatitude, 52.3676)
        XCTAssertEqual(box.minLongitude, 4.3517)
        XCTAssertEqual(box.maxLongitude, 4.9041)
        XCTAssertEqual(box.center.latitude, 51.60895, accuracy: 0.0001)
        XCTAssertNil(Geo.boundingBox(of: []))
        let padded = box.padded(by: 0.1)
        XCTAssertLessThan(padded.minLatitude, box.minLatitude)
        XCTAssertGreaterThan(padded.maxLongitude, box.maxLongitude)
    }

    func testWebMercatorRoundTrip() {
        let projected = Geo.webMercator(from: amsterdam)
        XCTAssertEqual(projected.x, 545_921.91, accuracy: 0.5)
        XCTAssertEqual(projected.y, 6_866_867.12, accuracy: 0.5)
        let back = Geo.point(fromWebMercatorX: projected.x, y: projected.y)
        XCTAssertEqual(back.latitude, amsterdam.latitude, accuracy: 0.000001)
        XCTAssertEqual(back.longitude, amsterdam.longitude, accuracy: 0.000001)
    }

    func testHikingDuration() {
        // 14.2 km with 620 m up and down: 12 780 s horizontal, 11 904 s vertical.
        XCTAssertEqual(Geo.hikingDuration(distance: 14_200, ascent: 620, descent: 620), 18_732, accuracy: 1)
        // Flat: exactly 4 km/h.
        XCTAssertEqual(Geo.hikingDuration(distance: 4_000, ascent: 0, descent: 0), 3_600, accuracy: 0.001)
    }

    func testSimplifyRemovesPointsOnAStraightLine() {
        let line = (0...100).map { GeoPoint(latitude: 50 + Double($0) * 0.001, longitude: 10) }
        let simplified = Geo.simplify(line, tolerance: 5)
        XCTAssertEqual(simplified.count, 2)
        XCTAssertEqual(simplified.first, line.first)
        XCTAssertEqual(simplified.last, line.last)
    }

    func testSimplifyKeepsCorners() {
        let line = [
            GeoPoint(latitude: 50, longitude: 10),
            GeoPoint(latitude: 50.01, longitude: 10),
            GeoPoint(latitude: 50.01, longitude: 10.02),
        ]
        XCTAssertEqual(Geo.simplify(line, tolerance: 5).count, 3)
    }

    func testDownsample() {
        let line = (0..<1000).map { GeoPoint(latitude: 50 + Double($0) * 0.0001, longitude: 10) }
        let reduced = Geo.downsample(line, maxCount: 100)
        XCTAssertEqual(reduced.count, 100)
        XCTAssertEqual(reduced.first, line.first)
        XCTAssertEqual(reduced.last, line.last)
        XCTAssertEqual(Geo.downsample(line, maxCount: 5000).count, 1000)
    }

    func testElevationProfileSamples() {
        let points = (0..<500).map {
            GeoPoint(latitude: 50 + Double($0) * 0.0001, longitude: 10, elevation: 100 + Double($0))
        }
        let samples = ElevationProfile.samples(for: points, maxSamples: 50)
        XCTAssertEqual(samples.count, 50)
        XCTAssertEqual(samples.first?.elevation, 100)
        XCTAssertEqual(samples.last?.elevation, 599)
        XCTAssertTrue(zip(samples, samples.dropFirst()).allSatisfy { $0.distance < $1.distance })
        XCTAssertTrue(ElevationProfile.samples(for: [amsterdam, brussels]).isEmpty)
    }
}
