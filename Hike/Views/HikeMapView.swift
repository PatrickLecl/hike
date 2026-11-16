import MapKit
import SwiftUI

/// A line drawn on the map.
struct MapLine: Identifiable, Equatable {
    enum Style {
        /// The planned or saved route: vermilion.
        case route
        /// A route shown for reference while recording: dashed ink.
        case reference
        /// What has been walked so far: glacier blue.
        case recorded
    }

    let id: String
    let points: [GeoPoint]
    let style: Style
    /// Cheap fingerprint so long lines are not compared point by point on every update.
    private let signature: Int

    init(id: String, points: [GeoPoint], style: Style = .route) {
        self.id = id
        self.points = points
        self.style = style
        var hasher = Hasher()
        hasher.combine(points.count)
        hasher.combine(points.first)
        hasher.combine(points.last)
        if points.count > 2 { hasher.combine(points[points.count / 2]) }
        signature = hasher.finalize()
    }

    static func == (lhs: MapLine, rhs: MapLine) -> Bool {
        lhs.id == rhs.id && lhs.style == rhs.style && lhs.signature == rhs.signature
    }
}

/// A numbered marker on the map.
struct MapPin: Identifiable, Equatable {
    let id: String
    let point: GeoPoint
    let label: String
}

/// A request to move the camera. A new `id` triggers the move.
struct MapFocus: Equatable {
    enum Target: Equatable {
        case box(BoundingBox)
        case point(GeoPoint, meters: Double)
        case user
    }

    let id = UUID()
    let target: Target

    static func box(_ box: BoundingBox) -> MapFocus { MapFocus(target: .box(box)) }
    static func point(_ point: GeoPoint, meters: Double = 4000) -> MapFocus {
        MapFocus(target: .point(point, meters: meters))
    }
    static var user: MapFocus { MapFocus(target: .user) }

    static func == (lhs: MapFocus, rhs: MapFocus) -> Bool { lhs.id == rhs.id }
}

/// The map used on every screen: topographic tiles (cached for offline use) or Apple's
/// maps, with route lines, numbered pins and the user's position.
struct HikeMapView: UIViewRepresentable {
    var layer: MapLayer = .outdoor
    var lines: [MapLine] = []
    var pins: [MapPin] = []
    var showsUser: Bool = false
    var focus: MapFocus?
    var bottomInset: CGFloat = 0
    var onTap: ((GeoPoint) -> Void)?
    var onRegionChange: ((BoundingBox) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.isPitchEnabled = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.pinIdentifier)
        // Start with all of Europe in view.
        mapView.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 49.5, longitude: 9.5),
                span: MKCoordinateSpan(latitudeDelta: 28, longitudeDelta: 34)
            ),
            animated: false
        )

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        // Let the map's own double-tap zoom win over our single tap.
        for view in mapView.subviews {
            for recognizer in view.gestureRecognizers ?? [] {
                if let doubleTap = recognizer as? UITapGestureRecognizer, doubleTap.numberOfTapsRequired == 2 {
                    tap.require(toFail: doubleTap)
                }
            }
        }
        mapView.addGestureRecognizer(tap)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        if mapView.showsUserLocation != showsUser {
            mapView.showsUserLocation = showsUser
        }
        if mapView.layoutMargins.bottom != bottomInset {
            mapView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        }
        coordinator.apply(layer: layer, to: mapView)
        coordinator.apply(lines: lines, to: mapView)
        coordinator.apply(pins: pins, to: mapView)
        if let focus, focus.id != coordinator.lastFocusID {
            coordinator.lastFocusID = focus.id
            coordinator.apply(focus: focus, to: mapView)
        }
    }

    final class StyledPolyline: MKPolyline {
        var style: MapLine.Style = .route
    }

    final class PinAnnotation: NSObject, MKAnnotation {
        let coordinate: CLLocationCoordinate2D
        let label: String

        init(pin: MapPin) {
            coordinate = pin.point.coordinate
            label = pin.label
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        static let pinIdentifier = "pin"

        var parent: HikeMapView
        var lastFocusID: UUID?
        private var currentLayer: MapLayer?
        private var tileOverlay: CachedTileOverlay?
        private var currentLines: [MapLine] = []
        private var lineOverlays: [String: StyledPolyline] = [:]
        private var currentPins: [MapPin] = []

        init(_ parent: HikeMapView) {
            self.parent = parent
        }

        // MARK: Applying state

        func apply(layer: MapLayer, to mapView: MKMapView) {
            guard layer != currentLayer else { return }
            currentLayer = layer
            if let tileOverlay {
                mapView.removeOverlay(tileOverlay)
                self.tileOverlay = nil
            }
            switch layer {
            case .outdoor:
                mapView.mapType = .standard
                let overlay = CachedTileOverlay()
                tileOverlay = overlay
                mapView.insertOverlay(overlay, at: 0, level: .aboveLabels)
                // The tiles end at a fixed zoom level; don't let the camera go closer.
                mapView.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 900)
            case .standard:
                mapView.mapType = .standard
                mapView.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 150)
            case .satellite:
                mapView.mapType = .hybrid
                mapView.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 150)
            }
        }

        func apply(lines: [MapLine], to mapView: MKMapView) {
            guard lines != currentLines else { return }
            let newIDs = Set(lines.map(\.id))
            for (id, overlay) in lineOverlays where !newIDs.contains(id) {
                mapView.removeOverlay(overlay)
                lineOverlays[id] = nil
            }
            let previous = Dictionary(currentLines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for line in lines {
                if previous[line.id] == line, lineOverlays[line.id] != nil { continue }
                if let old = lineOverlays[line.id] { mapView.removeOverlay(old) }
                guard line.points.count >= 2 else {
                    lineOverlays[line.id] = nil
                    continue
                }
                let coordinates = line.points.map(\.coordinate)
                let polyline = StyledPolyline(coordinates: coordinates, count: coordinates.count)
                polyline.style = line.style
                lineOverlays[line.id] = polyline
                mapView.addOverlay(polyline, level: .aboveLabels)
            }
            currentLines = lines
        }

        func apply(pins: [MapPin], to mapView: MKMapView) {
            guard pins != currentPins else { return }
            currentPins = pins
            mapView.removeAnnotations(mapView.annotations.filter { $0 is PinAnnotation })
            mapView.addAnnotations(pins.map { PinAnnotation(pin: $0) })
        }

        func apply(focus: MapFocus, to mapView: MKMapView) {
            switch focus.target {
            case .box(let box):
                let padded = box.padded(by: 0.15)
                let region = MKCoordinateRegion(
                    center: padded.center.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: padded.latitudeSpan, longitudeDelta: padded.longitudeSpan)
                )
                mapView.setRegion(mapView.regionThatFits(region), animated: true)
            case .point(let point, let meters):
                let region = MKCoordinateRegion(
                    center: point.coordinate, latitudinalMeters: meters, longitudinalMeters: meters
                )
                mapView.setRegion(mapView.regionThatFits(region), animated: true)
            case .user:
                mapView.setUserTrackingMode(.follow, animated: true)
            }
        }

        // MARK: Gestures

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let mapView = recognizer.view as? MKMapView,
                  let onTap = parent.onTap
            else { return }
            let location = recognizer.location(in: mapView)
            let coordinate = mapView.convert(location, toCoordinateFrom: mapView)
            guard CLLocationCoordinate2DIsValid(coordinate) else { return }
            onTap(GeoPoint(coordinate))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // Taps on pins and map controls are not taps on the map.
            var view = touch.view
            while let current = view {
                if current is MKAnnotationView || current is UIControl { return false }
                view = current.superview
            }
            return true
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tiles)
            }
            guard let polyline = overlay as? StyledPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.lineCap = .round
            renderer.lineJoin = .round
            switch polyline.style {
            case .route:
                renderer.strokeColor = Theme.uiBlaze
                renderer.lineWidth = 5
            case .reference:
                renderer.strokeColor = Theme.uiSpruce.withAlphaComponent(0.75)
                renderer.lineWidth = 4
                renderer.lineDashPattern = [2, 8]
            case .recorded:
                renderer.strokeColor = Theme.uiGlacier
                renderer.lineWidth = 5
            }
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? PinAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.pinIdentifier, for: pin)
            view.image = Self.pinImage(label: pin.label)
            view.canShowCallout = false
            view.displayPriority = .required
            view.accessibilityLabel = pin.label
            return view
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard let onRegionChange = parent.onRegionChange else { return }
            let region = mapView.region
            let box = BoundingBox(
                minLatitude: region.center.latitude - region.span.latitudeDelta / 2,
                maxLatitude: region.center.latitude + region.span.latitudeDelta / 2,
                minLongitude: region.center.longitude - region.span.longitudeDelta / 2,
                maxLongitude: region.center.longitude + region.span.longitudeDelta / 2
            )
            // The map can report a region while SwiftUI is still updating the view.
            DispatchQueue.main.async { onRegionChange(box) }
        }

        /// A vermilion disc with a paper rim and the waypoint number.
        private static func pinImage(label: String) -> UIImage {
            let size = CGSize(width: 30, height: 30)
            return UIGraphicsImageRenderer(size: size).image { _ in
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
                Theme.uiChalk.setFill()
                UIBezierPath(ovalIn: rect).fill()
                Theme.uiBlaze.setFill()
                UIBezierPath(ovalIn: rect.insetBy(dx: 2.5, dy: 2.5)).fill()

                let font = UIFont.systemFont(ofSize: 13, weight: .bold)
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
                let text = label as NSString
                let textSize = text.size(withAttributes: attributes)
                text.draw(
                    at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                    withAttributes: attributes
                )
            }
        }
    }
}

/// Credit line required by the map data providers; sits in a corner of the map.
struct MapAttribution: View {
    var layer: MapLayer

    var body: some View {
        if layer == .outdoor {
            Text(verbatim: AppConfig.outdoorTileAttribution)
                .font(.system(size: 9))
                .foregroundStyle(Color.black.opacity(0.7))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                .accessibilityHidden(true)
        }
    }
}
