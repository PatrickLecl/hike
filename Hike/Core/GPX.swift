import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct GPXWaypoint: Hashable, Sendable {
    var name: String?
    var point: GeoPoint
}

/// The parts of a GPX file Hike understands.
struct GPXDocument: Sendable {
    var name: String?
    /// One array of points per `<trk>` (segments joined) and per `<rte>`.
    var lines: [[GeoPoint]] = []
    var waypoints: [GPXWaypoint] = []

    /// All lines joined into one, in file order.
    var allPoints: [GeoPoint] { lines.flatMap { $0 } }
}

enum GPXError: Error {
    case invalidFile
    case empty
}

enum GPXParser {
    static func parse(_ data: Data) throws -> GPXDocument {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw GPXError.invalidFile }
        var document = delegate.document
        document.lines.removeAll { $0.isEmpty }
        guard !document.lines.isEmpty || !document.waypoints.isEmpty else { throw GPXError.empty }
        return document
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        var document = GPXDocument()

        private var path: [String] = []
        private var text = ""
        private var currentLine: [GeoPoint]?
        private var currentPoint: GeoPoint?
        private var currentPointName: String?

        func parser(
            _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
            qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
        ) {
            let name = elementName.lowercased()
            path.append(name)
            text = ""
            switch name {
            case "trk", "rte":
                currentLine = []
            case "trkpt", "rtept", "wpt":
                if let lat = attributeDict["lat"].flatMap({ Double($0) }),
                   let lon = attributeDict["lon"].flatMap({ Double($0) }) {
                    currentPoint = GeoPoint(latitude: lat, longitude: lon)
                } else {
                    currentPoint = nil
                }
                currentPointName = nil
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(
            _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let name = elementName.lowercased()
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let parent = path.count >= 2 ? path[path.count - 2] : ""
            let isInsidePoint = ["trkpt", "rtept", "wpt"].contains(parent)

            switch name {
            case "ele" where isInsidePoint:
                if let elevation = Double(value), elevation.isFinite { currentPoint?.elevation = elevation }
            case "time" where isInsidePoint:
                currentPoint?.time = GPXDate.parse(value)
            case "name":
                if isInsidePoint {
                    currentPointName = value.isEmpty ? nil : value
                } else if ["trk", "rte", "metadata"].contains(parent), document.name == nil, !value.isEmpty {
                    document.name = value
                }
            case "trkpt", "rtept":
                if let point = currentPoint, point.isValid { currentLine?.append(point) }
                currentPoint = nil
            case "wpt":
                if let point = currentPoint, point.isValid {
                    document.waypoints.append(GPXWaypoint(name: currentPointName, point: point))
                }
                currentPoint = nil
            case "trk", "rte":
                if let line = currentLine { document.lines.append(line) }
                currentLine = nil
            default:
                break
            }
            path.removeLast()
            text = ""
        }
    }
}

enum GPXWriter {
    /// Serialises a track (and optional waypoints) as GPX 1.1.
    static func string(name: String, points: [GeoPoint], waypoints: [GPXWaypoint] = [], creator: String = "Hike") -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<gpx version=\"1.1\" creator=\"\(escape(creator))\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n"
        xml += "  <metadata><name>\(escape(name))</name></metadata>\n"
        for waypoint in waypoints {
            xml += "  <wpt lat=\"\(format(waypoint.point.latitude))\" lon=\"\(format(waypoint.point.longitude))\">"
            if let waypointName = waypoint.name { xml += "<name>\(escape(waypointName))</name>" }
            xml += "</wpt>\n"
        }
        xml += "  <trk>\n    <name>\(escape(name))</name>\n    <trkseg>\n"
        for point in points {
            xml += "      <trkpt lat=\"\(format(point.latitude))\" lon=\"\(format(point.longitude))\">"
            if let elevation = point.elevation, elevation.isFinite {
                xml += "<ele>\(String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), elevation))</ele>"
            }
            if let time = point.time { xml += "<time>\(GPXDate.string(from: time))</time>" }
            xml += "</trkpt>\n"
        }
        xml += "    </trkseg>\n  </trk>\n</gpx>\n"
        return xml
    }

    private static func format(_ degrees: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), degrees)
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

enum GPXDate {
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ value: String) -> Date? {
        withFraction.date(from: value) ?? plain.date(from: value)
    }

    static func string(from date: Date) -> String {
        plain.string(from: date)
    }
}
