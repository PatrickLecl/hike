import XCTest
@testable import HikeCore

final class GPXTests: XCTestCase {
    private let sample = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="Test" xmlns="http://www.topografix.com/GPX/1/1">
      <metadata><name>Mullerthal &amp; more</name></metadata>
      <wpt lat="49.8153" lon="6.4215"><name>Echternach</name></wpt>
      <trk>
        <name>Track name</name>
        <trkseg>
          <trkpt lat="49.8153" lon="6.4215"><ele>160.5</ele><time>2026-05-01T08:00:00Z</time></trkpt>
          <trkpt lat="49.8160" lon="6.4230"><ele>172</ele><time>2026-05-01T08:01:30Z</time></trkpt>
        </trkseg>
        <trkseg>
          <trkpt lat="49.8171" lon="6.4244"><ele>181.2</ele></trkpt>
          <trkpt lat="999" lon="6.4244"></trkpt>
        </trkseg>
      </trk>
    </gpx>
    """

    func testParsesTracksWaypointsAndName() throws {
        let document = try GPXParser.parse(Data(sample.utf8))
        XCTAssertEqual(document.name, "Mullerthal & more")
        XCTAssertEqual(document.lines.count, 1)
        // The invalid point (latitude 999) is dropped.
        XCTAssertEqual(document.allPoints.count, 3)
        XCTAssertEqual(document.allPoints[0].elevation, 160.5)
        XCTAssertEqual(document.allPoints[1].latitude, 49.8160)
        XCTAssertEqual(document.allPoints[0].time, GPXDate.parse("2026-05-01T08:00:00Z"))
        XCTAssertNil(document.allPoints[2].time)
        XCTAssertEqual(document.waypoints.count, 1)
        XCTAssertEqual(document.waypoints[0].name, "Echternach")
    }

    func testParsesRoutes() throws {
        let gpx = """
        <gpx version="1.1"><rte><name>Loop</name>
        <rtept lat="46.0" lon="7.0"/><rtept lat="46.1" lon="7.1"/></rte></gpx>
        """
        let document = try GPXParser.parse(Data(gpx.utf8))
        XCTAssertEqual(document.name, "Loop")
        XCTAssertEqual(document.allPoints.count, 2)
    }

    func testRejectsInvalidAndEmptyFiles() {
        XCTAssertThrowsError(try GPXParser.parse(Data("not xml at all <".utf8)))
        XCTAssertThrowsError(try GPXParser.parse(Data("<gpx version=\"1.1\"></gpx>".utf8)))
    }

    func testWriterRoundTrip() throws {
        let time = try XCTUnwrap(GPXDate.parse("2026-07-14T09:30:00Z"))
        let points = [
            GeoPoint(latitude: 45.8326, longitude: 6.8652, elevation: 1035.4, time: time),
            GeoPoint(latitude: 45.8401, longitude: 6.8701, elevation: 1180),
            GeoPoint(latitude: 45.8455, longitude: 6.8755),
        ]
        let waypoints = [GPXWaypoint(name: "1", point: points[0])]
        let xml = GPXWriter.string(name: "Tour <du> Mont Blanc & \"more\"", points: points, waypoints: waypoints)

        let document = try GPXParser.parse(Data(xml.utf8))
        XCTAssertEqual(document.name, "Tour <du> Mont Blanc & \"more\"")
        XCTAssertEqual(document.allPoints.count, 3)
        XCTAssertEqual(document.allPoints[0].latitude, 45.8326, accuracy: 0.000001)
        XCTAssertEqual(document.allPoints[0].longitude, 6.8652, accuracy: 0.000001)
        XCTAssertEqual(document.allPoints[0].elevation ?? 0, 1035.4, accuracy: 0.05)
        XCTAssertEqual(document.allPoints[0].time, time)
        XCTAssertNil(document.allPoints[2].elevation)
        XCTAssertEqual(document.waypoints.count, 1)
    }

    func testDateParsingWithFractionalSeconds() {
        XCTAssertNotNil(GPXDate.parse("2026-05-01T08:00:00.123Z"))
        XCTAssertNotNil(GPXDate.parse("2026-05-01T08:00:00+02:00"))
        XCTAssertNil(GPXDate.parse("yesterday"))
    }
}
