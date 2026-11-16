import XCTest
@testable import HikeCore

final class TileMathTests: XCTestCase {
    func testTileForCoordinate() {
        XCTAssertEqual(TileMath.tile(latitude: 46.8523, longitude: 9.5303, zoom: 12), TileCoordinate(x: 2156, y: 1443, z: 12))
        XCTAssertEqual(TileMath.tile(latitude: 52.3676, longitude: 4.9041, zoom: 10), TileCoordinate(x: 525, y: 336, z: 10))
        XCTAssertEqual(TileMath.tile(latitude: 0, longitude: 0, zoom: 0), TileCoordinate(x: 0, y: 0, z: 0))
        // Out-of-range input stays inside the tile grid.
        XCTAssertEqual(TileMath.tile(latitude: 89.9, longitude: 180, zoom: 3), TileCoordinate(x: 7, y: 0, z: 3))
    }

    func testTilesAlongRouteIncludeBufferAndFillGaps() {
        let point = GeoPoint(latitude: 46.8523, longitude: 9.5303)
        let single = TileMath.tiles(along: [point], zooms: 12...12, buffer: 1)
        XCTAssertEqual(single.count, 9)
        XCTAssertTrue(single.contains(TileCoordinate(x: 2156, y: 1443, z: 12)))

        // Two points several tiles apart: every tile in between must be covered.
        let far = GeoPoint(latitude: 46.8523, longitude: 9.9)
        let tiles = TileMath.tiles(along: [point, far], zooms: 12...12, buffer: 0)
        let endX = TileMath.tile(latitude: far.latitude, longitude: far.longitude, zoom: 12).x
        for x in 2156...endX {
            XCTAssertTrue(tiles.contains(TileCoordinate(x: x, y: 1443, z: 12)), "missing tile x=\(x)")
        }

        let multiZoom = TileMath.tiles(along: [point], zooms: 11...13, buffer: 0)
        XCTAssertEqual(Set(multiZoom.map(\.z)), [11, 12, 13])
    }

    func testURLTemplate() {
        let tile = TileCoordinate(x: 2156, y: 1443, z: 12)
        XCTAssertEqual(
            TileMath.url(template: "https://tile.example.org/{z}/{x}/{y}.png", tile: tile)?.absoluteString,
            "https://tile.example.org/12/2156/1443.png"
        )
        let withSubdomain = TileMath.url(template: "https://{s}.example.org/{z}/{x}/{y}.png", tile: tile)
        XCTAssertNotNil(withSubdomain)
        XCTAssertFalse(withSubdomain?.absoluteString.contains("{") ?? true)
    }
}

final class OpenRouteServiceTests: XCTestCase {
    func testDirectionsBody() throws {
        let body = try OpenRouteService.directionsBody(waypoints: [
            GeoPoint(latitude: 46.0, longitude: 7.5),
            GeoPoint(latitude: 46.1, longitude: 7.6),
        ])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let coordinates = try XCTUnwrap(json["coordinates"] as? [[Double]])
        // openrouteservice expects longitude first.
        XCTAssertEqual(coordinates, [[7.5, 46.0], [7.6, 46.1]])
        XCTAssertEqual(json["elevation"] as? Bool, true)
        XCTAssertThrowsError(try OpenRouteService.directionsBody(waypoints: []))
    }

    func testDecodeDirections() throws {
        let response = """
        {"type":"FeatureCollection","features":[{"type":"Feature",
          "properties":{"ascent":120.5,"descent":10.0,"summary":{"distance":2500.0,"duration":2100.0}},
          "geometry":{"type":"LineString","coordinates":[[7.5,46.0,1500.0],[7.51,46.01,1560.2],[7.52,46.02,1620]]}}]}
        """
        let route = try OpenRouteService.decodeDirections(Data(response.utf8))
        XCTAssertEqual(route.points.count, 3)
        XCTAssertEqual(route.points[0].latitude, 46.0)
        XCTAssertEqual(route.points[0].longitude, 7.5)
        XCTAssertEqual(route.points[1].elevation, 1560.2)
        XCTAssertTrue(route.hasElevation)
        XCTAssertEqual(route.ascent, 120, accuracy: 0.001)
        XCTAssertGreaterThan(route.distance, 2000)
        XCTAssertGreaterThan(route.duration, 0)
    }

    func testDecodeDirectionsError() {
        let response = """
        {"error":{"code":2010,"message":"Could not find routable point within a radius of 350.0 meters"}}
        """
        XCTAssertThrowsError(try OpenRouteService.decodeDirections(Data(response.utf8))) { error in
            guard case RoutingError.server(let message) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertTrue(message.contains("routable point"))
        }
        XCTAssertThrowsError(try OpenRouteService.decodeDirections(Data("{}".utf8)))
        XCTAssertEqual(OpenRouteService.errorMessage(in: Data("{\"error\":\"Access denied\"}".utf8)), "Access denied")
    }

    func testDecodeElevation() throws {
        let response = """
        {"attribution":"x","version":"0.2.1","timestamp":1,"geometry":[[13.349762,38.11295,72],[12.638397,37.645772,2]]}
        """
        let points = try OpenRouteService.decodeElevation(Data(response.utf8))
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].elevation, 72)
        XCTAssertEqual(points[1].latitude, 37.645772)
    }
}

final class WaymarkedTrailsTests: XCTestCase {
    func testURLs() throws {
        let search = try XCTUnwrap(WaymarkedTrails.searchURL(query: "GR 5"))
        XCTAssertTrue(search.absoluteString.hasPrefix("https://hiking.waymarkedtrails.org/api/v1/list/search?"))
        XCTAssertTrue(search.absoluteString.contains("query=GR%205"))

        let box = BoundingBox(minLatitude: 50.8, maxLatitude: 52.4, minLongitude: 4.3, maxLongitude: 4.9)
        let area = try XCTUnwrap(WaymarkedTrails.areaURL(box: box))
        let bbox = try XCTUnwrap(URLComponents(url: area, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "bbox" }?.value)
        let values = bbox.split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(values.count, 4)
        // Web Mercator metres, west/south/east/north.
        XCTAssertEqual(values[0], 478_674, accuracy: 2)
        XCTAssertLessThan(values[0], values[2])
        XCTAssertLessThan(values[1], values[3])

        let detail = WaymarkedTrails.detailURL(for: TrailSummary(id: 379910))
        XCTAssertEqual(detail?.absoluteString, "https://hiking.waymarkedtrails.org/api/v1/details/relation/379910")
    }

    func testDecodeList() throws {
        let response = """
        {"query":"GR 5","page":1,"results":[
          {"type":"relation","id":379910,"ref":"GR 5","name":"Sender dels Miradors","group":"NAT","linear":"yes",
           "itinerary":["Sitges","Canet de Mar"],"symbol_id":"osmc_NAT_white_red"},
          {"type":"relation","id":2343781,"group":"REG","linear":"yes","symbol_description":"Rotes M"}]}
        """
        let trails = try WaymarkedTrails.decodeList(Data(response.utf8))
        XCTAssertEqual(trails.count, 2)
        XCTAssertEqual(trails[0].title, "Sender dels Miradors")
        XCTAssertEqual(trails[0].network, .national)
        XCTAssertEqual(trails[0].itineraryText, "Sitges – Canet de Mar")
        XCTAssertEqual(trails[1].title, "#2343781")
        XCTAssertEqual(trails[1].network, .regional)
        XCTAssertEqual(trails[1].symbolDescription, "Rotes M")
        XCTAssertNil(trails[1].itineraryText)
        XCTAssertThrowsError(try WaymarkedTrails.decodeList(Data("{}".utf8)))
    }

    func testDecodeDetailStitchesWaysAndFollowsForwardBranch() throws {
        // Same nesting as the live API: route → linear → base ways, with a split whose
        // backward branch must be ignored, plus an appendix that is not part of the main line.
        let response = """
        {"type":"relation","id":42,"ref":"GR 5","name":"Test Trail","group":"INT",
         "official_length":201000.0,"operator":"Club","url":"https://example.org/trail",
         "description":"A - B",
         "route":{"route_type":"route","length":207640,"start":0,
          "main":[
           {"route_type":"linear","start":0,"length":60,"ways":[
             {"route_type":"base","id":1,"direction":0,"geometry":{"type":"LineString",
               "coordinates":[[201531.14,5048021.57],[201551.74,5048017.80]]}},
             {"route_type":"base","id":2,"direction":0,"geometry":{"type":"LineString",
               "coordinates":[[201551.74,5048017.80],[201566.66,5048019.87],[201570.91,5048020.86]]}}]},
           {"route_type":"split","start":60,"length":24,
            "forward":[{"route_type":"linear","ways":[
              {"route_type":"base","id":3,"direction":1,"geometry":{"type":"LineString",
                "coordinates":[[201570.91,5048020.86],[201600.00,5048030.00]]}}]}],
            "backward":[{"route_type":"linear","ways":[
              {"route_type":"base","id":3,"direction":-1,"geometry":{"type":"LineString",
                "coordinates":[[209999.00,5049999.00],[209998.00,5049998.00]]}}]}]},
           {"route_type":"linear","start":84,"length":50,"ways":[
             {"route_type":"base","id":4,"direction":0,"geometry":{"type":"LineString",
               "coordinates":[[203000.00,5049000.00],[203050.00,5049010.00]]}}]}],
          "appendices":[{"route_type":"appendix","main":[{"route_type":"linear","ways":[
             {"route_type":"base","id":9,"direction":0,"geometry":{"type":"LineString",
               "coordinates":[[100.0,100.0],[200.0,200.0]]}}]}]}]}}
        """
        let detail = try WaymarkedTrails.decodeDetail(Data(response.utf8))
        XCTAssertEqual(detail.summary.id, 42)
        XCTAssertEqual(detail.summary.title, "Test Trail")
        XCTAssertEqual(detail.summary.network, .international)
        XCTAssertEqual(detail.officialLength, 201_000)
        XCTAssertEqual(detail.mappedLength, 207_640)
        XCTAssertEqual(detail.length, 201_000)
        XCTAssertEqual(detail.operatorName, "Club")
        XCTAssertEqual(detail.website?.absoluteString, "https://example.org/trail")
        XCTAssertEqual(detail.summaryText, "A - B")

        // Ways 1–3 touch and become one segment of 5 points; way 4 starts elsewhere.
        XCTAssertEqual(detail.segments.count, 2)
        XCTAssertEqual(detail.segments[0].count, 5)
        XCTAssertEqual(detail.segments[1].count, 2)
        XCTAssertEqual(detail.segments[0][0].latitude, 41.241454, accuracy: 0.00001)
        XCTAssertEqual(detail.segments[0][0].longitude, 1.810385, accuracy: 0.00001)
        XCTAssertEqual(detail.allPoints.count, 7)
    }

    func testStitchReversesWaysThatRunBackwards() {
        let a = GeoPoint(latitude: 50, longitude: 10)
        let b = GeoPoint(latitude: 50.001, longitude: 10)
        let c = GeoPoint(latitude: 50.002, longitude: 10)
        let segments = WaymarkedTrails.stitch([[a, b], [c, b]])
        XCTAssertEqual(segments, [[a, b, c]])
    }

    func testDecodeDetailRejectsGarbage() {
        XCTAssertThrowsError(try WaymarkedTrails.decodeDetail(Data("[]".utf8)))
    }
}
