import SwiftData
import SwiftUI

/// Loads waymarked trails, either by name or for the area shown on the map.
@MainActor
final class DiscoverModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    @Published private(set) var trails: [TrailSummary] = []
    @Published private(set) var phase: Phase = .idle
    /// True when the list shows the result of a name search rather than an area.
    @Published private(set) var isSearchResult = false

    private var task: Task<Void, Never>?

    func search(_ query: String) {
        load(isSearch: true) { try await TrailService.search(query) }
    }

    func load(area: BoundingBox) {
        load(isSearch: false) { try await TrailService.trails(in: area) }
    }

    private func load(isSearch: Bool, _ operation: @escaping () async throws -> [TrailSummary]) {
        task?.cancel()
        phase = .loading
        task = Task {
            do {
                let result = try await operation()
                guard !Task.isCancelled else { return }
                trails = result
                isSearchResult = isSearch
                phase = .loaded
            } catch {
                guard !Task.isCancelled else { return }
                trails = []
                phase = .failed
            }
        }
    }
}

struct DiscoverView: View {
    /// All of Europe, used for the first load.
    private static let europe = BoundingBox(minLatitude: 35, maxLatitude: 71, minLongitude: -11, maxLongitude: 32)

    @EnvironmentObject private var tracker: LocationTracker
    @StateObject private var model = DiscoverModel()
    @AppStorage("mapLayer") private var layerRaw = MapLayer.outdoor.rawValue

    @State private var query = ""
    @State private var network: TrailNetwork?
    @State private var visibleArea = DiscoverView.europe
    @State private var loadedArea: BoundingBox?
    @State private var focus: MapFocus?

    private var layer: MapLayer { MapLayer(rawValue: layerRaw) ?? .outdoor }

    private var filteredTrails: [TrailSummary] {
        guard let network else { return model.trails }
        return model.trails.filter { $0.network == network }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenTitle(text: "Discover")
                    searchField
                    areaMap
                    chips
                    results
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Theme.paper)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TrailSummary.self) { trail in
                TrailDetailView(trail: trail)
            }
        }
        .task {
            if model.phase == .idle { loadArea() }
        }
    }

    // MARK: Sections

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkSoft)
            TextField("Search trails", text: $query)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { submitSearch() }
            if !query.isEmpty {
                Button {
                    query = ""
                    loadArea()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkSoft)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    private var areaMap: some View {
        ZStack(alignment: .bottom) {
            HikeMapView(
                layer: layer,
                showsUser: tracker.isAuthorized,
                focus: focus,
                onRegionChange: { box in visibleArea = box }
            )
            HStack(alignment: .bottom) {
                MapAttribution(layer: layer)
                Spacer()
            }
            .padding(6)

            if loadedArea != visibleArea || model.isSearchResult {
                Button {
                    query = ""
                    loadArea()
                } label: {
                    Label("Trails in this area", systemImage: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.paper)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.ink, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 26)
            }
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            MapButton(systemImage: "location", label: "My location") {
                tracker.startUpdating()
                if let location = tracker.lastLocation {
                    focus = .point(GeoPoint(location.coordinate), meters: 30000)
                }
            }
            .padding(10)
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TrailNetwork.allCases, id: \.self) { item in
                    ChipView(title: item.title, isSelected: network == item) {
                        network = network == item ? nil : item
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        switch model.phase {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        case .failed:
            EmptyStateView(
                title: "Trails could not be loaded",
                message: "Check your connection and try again."
            )
        case .loaded:
            if filteredTrails.isEmpty {
                EmptyStateView(
                    title: "No trails found",
                    message: "Move the map, change the filter or search by name."
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredTrails) { trail in
                        NavigationLink(value: trail) {
                            TrailRow(trail: trail)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func submitSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            loadArea()
        } else {
            model.search(trimmed)
        }
    }

    private func loadArea() {
        loadedArea = visibleArea
        model.load(area: visibleArea)
    }
}

/// One trail in the Discover list.
struct TrailRow: View {
    var trail: TrailSummary

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            BlazeMark(accent: trail.network?.accent ?? Theme.blaze, width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: trail.title)
                    .font(.display(18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                if let itinerary = trail.itineraryText {
                    Text(verbatim: itinerary)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    if let ref = trail.ref, !ref.isEmpty, ref != trail.title {
                        Text(verbatim: ref)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    if let network = trail.network {
                        Text(network.title)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
        }
        .hikeCard()
        .contentShape(Rectangle())
    }
}
