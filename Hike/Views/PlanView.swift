import MapKit
import SwiftData
import SwiftUI

/// Holds the route being drawn and recalculates it whenever the waypoints change.
@MainActor
final class PlanModel: ObservableObject {
    @Published private(set) var waypoints: [GeoPoint] = []
    @Published private(set) var route: PlannedRoute?
    @Published private(set) var isRouting = false
    @Published var errorMessage: String?

    private let routing = RoutingService()
    private var task: Task<Void, Never>?

    func add(_ point: GeoPoint) {
        waypoints.append(point)
        recalculate()
    }

    func undo() {
        guard !waypoints.isEmpty else { return }
        waypoints.removeLast()
        recalculate()
    }

    func clear() {
        waypoints = []
        recalculate()
    }

    /// Adds the starting point as the final waypoint, turning the route into a loop.
    func returnToStart() {
        guard let first = waypoints.first, waypoints.count >= 2, waypoints.last != first else { return }
        waypoints.append(first)
        recalculate()
    }

    var canReturnToStart: Bool {
        waypoints.count >= 2 && waypoints.last != waypoints.first
    }

    private func recalculate() {
        task?.cancel()
        errorMessage = nil
        guard waypoints.count >= 2 else {
            route = nil
            isRouting = false
            return
        }
        isRouting = true
        let current = waypoints
        task = Task {
            do {
                let result = try await routing.route(through: current)
                guard !Task.isCancelled else { return }
                route = result
            } catch {
                guard !Task.isCancelled else { return }
                // Keep something on the map: straight lines between the waypoints.
                route = PlannedRoute(points: current)
                errorMessage = Self.message(for: error)
            }
            isRouting = false
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case RoutingError.noRouteFound:
            return String(localized: "No walking route found between these points. Showing a straight line instead.")
        case RoutingError.server(let detail):
            return String(localized: "The route service reported a problem.") + " " + detail
        default:
            return String(localized: "The route could not be calculated. Check your connection.")
        }
    }
}

struct PlanView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var tracker: LocationTracker
    @Environment(\.modelContext) private var modelContext
    @StateObject private var model = PlanModel()
    @AppStorage("mapLayer") private var layerRaw = MapLayer.outdoor.rawValue

    @State private var focus: MapFocus?
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchFailed = false
    @State private var showSavePrompt = false
    @State private var hikeName = ""
    @State private var showSavedConfirmation = false
    @FocusState private var searchFocused: Bool

    private var layer: MapLayer { MapLayer(rawValue: layerRaw) ?? .outdoor }

    var body: some View {
        ZStack(alignment: .bottom) {
            HikeMapView(
                layer: layer,
                lines: mapLines,
                pins: mapPins,
                showsUser: tracker.isAuthorized,
                focus: focus,
                bottomInset: 200,
                onTap: { point in
                    searchFocused = false
                    model.add(point)
                }
            )
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                HStack {
                    MapAttribution(layer: layer)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                panel
            }
        }
        .background(Theme.paper)
        .alert("Name your hike", isPresented: $showSavePrompt) {
            TextField("Name", text: $hikeName)
            Button("Save") { save() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Place not found", isPresented: $searchFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try a town, region or mountain name.")
        }
        .alert("Saved to My hikes", isPresented: $showSavedConfirmation) {
            Button("Show") { appState.tab = .library }
            Button("Keep planning", role: .cancel) {}
        }
    }

    // MARK: Map content

    private var mapLines: [MapLine] {
        guard let route = model.route else { return [] }
        return [MapLine(id: "plan", points: route.points, style: .route)]
    }

    private var mapPins: [MapPin] {
        model.waypoints.enumerated().map { index, point in
            MapPin(id: "wp-\(index)", point: point, label: String(index + 1))
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.inkSoft)
                TextField("Search place", text: $searchText)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { searchPlace() }
                if isSearching {
                    ProgressView().controlSize(.small)
                } else if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkSoft)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear search"))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)

            VStack(spacing: 10) {
                Menu {
                    Picker("Map", selection: $layerRaw) {
                        Text("Topographic").tag(MapLayer.outdoor.rawValue)
                        Text("Standard").tag(MapLayer.standard.rawValue)
                        Text("Satellite").tag(MapLayer.satellite.rawValue)
                    }
                } label: {
                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 44, height: 44)
                        .background(Theme.card, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                }
                .accessibilityLabel(Text("Map"))

                MapButton(systemImage: "location", label: "My location") {
                    tracker.startUpdating()
                    if tracker.isAuthorized { focus = .user }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    // MARK: Bottom panel

    private var hint: LocalizedStringKey {
        model.waypoints.isEmpty
            ? "Tap the map to set your starting point."
            : "Tap the map again to add the next point."
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("Plan")
                    .font(.display(30))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if model.isRouting {
                    ProgressView().controlSize(.small).padding(.leading, 4)
                }
                Spacer()
                if !model.waypoints.isEmpty {
                    Button {
                        model.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .accessibilityLabel(Text("Undo last point"))
                    Button {
                        model.returnToStart()
                    } label: {
                        Image(systemName: "arrow.triangle.capsulepath")
                    }
                    .disabled(!model.canReturnToStart)
                    .accessibilityLabel(Text("Back to start"))
                    Button(role: .destructive) {
                        model.clear()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(Text("Clear route"))
                }
            }
            .font(.system(size: 17, weight: .semibold))
            .tint(Theme.ink)
            .buttonStyle(.borderless)

            if let route = model.route {
                routeSummary(route)
            } else {
                Text(hint)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 6)
            }
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous)
                .fill(Theme.paper)
                .shadow(color: .black.opacity(0.14), radius: 12, y: -2)
        )
    }

    @ViewBuilder
    private func routeSummary(_ route: PlannedRoute) -> some View {
        let distance = Format.distanceParts(route.distance)
        HStack(alignment: .top, spacing: 0) {
            StatView(label: "Distance", value: distance.value, unit: distance.unit)
                .frame(maxWidth: .infinity, alignment: .leading)
            StatView(
                label: "Ascent",
                value: route.hasElevation ? Format.meters(route.ascent) : "–",
                unit: route.hasElevation ? "m" : ""
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            StatView(label: "Est. time", value: Format.duration(route.duration))
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        let samples = ElevationProfile.samples(for: route.points)
        if samples.count > 2 {
            ElevationChart(samples: samples)
                .frame(height: 92)
        }

        if let message = model.errorMessage {
            Text(verbatim: message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.blaze)
        }

        Button("Save hike") {
            hikeName = ""
            showSavePrompt = true
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(model.isRouting)
    }

    // MARK: Actions

    private func save() {
        guard let route = model.route else { return }
        let trimmed = hikeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty
            ? String(localized: "Hike") + " " + Format.date(Date())
            : trimmed
        let hike = SavedHike(name: name, kind: .planned, points: route.points, waypoints: model.waypoints)
        modelContext.insert(hike)
        showSavedConfirmation = true
    }

    private func searchPlace() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        searchFocused = false
        isSearching = true
        Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            // Bias results towards Europe.
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 50, longitude: 10),
                span: MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 60)
            )
            let response = try? await MKLocalSearch(request: request).start()
            isSearching = false
            if let item = response?.mapItems.first {
                focus = .point(GeoPoint(item.placemark.coordinate), meters: 12000)
            } else {
                searchFailed = true
            }
        }
    }
}
