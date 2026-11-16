import Combine
import CoreLocation
import Foundation

/// Owns the location manager: shows where you are and records hikes.
final class LocationTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum RecordingState {
        case idle
        case recording
        case paused
    }

    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var lastLocation: CLLocation?
    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var points: [GeoPoint] = []
    /// Metres walked in the current recording.
    @Published private(set) var distance: Double = 0
    @Published private(set) var ascent: Double = 0

    private let manager = CLLocationManager()
    private var accumulatedTime: TimeInterval = 0
    private var resumedAt: Date?

    override init() {
        super.init()
        authorization = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    func requestPermission() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Starts location updates for showing the position on the map. Asks for permission
    /// the first time.
    func startUpdating() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if isAuthorized {
            manager.startUpdatingLocation()
        }
    }

    // MARK: Recording

    /// Time walked so far, not counting pauses.
    func elapsed(at date: Date = Date()) -> TimeInterval {
        accumulatedTime + (resumedAt.map { max(date.timeIntervalSince($0), 0) } ?? 0)
    }

    func startRecording() {
        guard isAuthorized, state == .idle else { return }
        points = []
        distance = 0
        ascent = 0
        accumulatedTime = 0
        resumedAt = Date()
        state = .recording
        // Keep receiving positions while the phone is locked or another app is open.
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    func pauseRecording() {
        guard state == .recording else { return }
        accumulatedTime = elapsed()
        resumedAt = nil
        state = .paused
    }

    func resumeRecording() {
        guard state == .paused else { return }
        resumedAt = Date()
        state = .recording
    }

    /// Ends the recording and returns what was walked.
    func finishRecording() -> (points: [GeoPoint], duration: TimeInterval) {
        let result = (points, elapsed())
        manager.allowsBackgroundLocationUpdates = false
        accumulatedTime = 0
        resumedAt = nil
        state = .idle
        points = []
        distance = 0
        ascent = 0
        return result
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if isAuthorized {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50 else { continue }
            lastLocation = location
            guard state == .recording else { continue }

            let point = GeoPoint(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                elevation: location.verticalAccuracy > 0 ? location.altitude : nil,
                time: location.timestamp
            )
            if let previous = points.last {
                let step = Geo.distance(previous, point)
                // Ignore jitter while standing still.
                guard step >= 4 else { continue }
                distance += step
            }
            points.append(point)
            ascent = Geo.elevationGain(of: points, threshold: 5).ascent
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Temporary failures (no fix yet, tunnel) resolve themselves; nothing to do.
    }
}
