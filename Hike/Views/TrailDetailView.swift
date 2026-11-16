import SwiftData
import SwiftUI

/// A waymarked trail: map, key facts and the option to keep it in My hikes.
struct TrailDetailView: View {
    var trail: TrailSummary

    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @AppStorage("mapLayer") private var layerRaw = MapLayer.outdoor.rawValue

    @State private var detail: TrailDetail?
    @State private var loadFailed = false
    @State private var focus: MapFocus?
    @State private var elevationPoints: [GeoPoint]?
    @State private var saved = false

    private var layer: MapLayer { MapLayer(rawValue: layerRaw) ?? .outdoor }

    private var lines: [MapLine] {
        guard let detail else { return [] }
        return detail.segments.enumerated().map { index, points in
            MapLine(id: "trail-\(index)", points: points, style: .route)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZStack(alignment: .bottomLeading) {
                    HikeMapView(layer: layer, lines: lines, focus: focus)
                    MapAttribution(layer: layer).padding(6)
                }
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )

                header

                if let detail {
                    facts(detail)
                } else if loadFailed {
                    EmptyStateView(
                        title: "Trail could not be loaded",
                        message: "Check your connection and try again."
                    )
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.vertical, 12)
        }
        .background(Theme.paper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.paper, for: .navigationBar)
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            BlazeMark(accent: trail.network?.accent ?? Theme.blaze, width: 44)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: trail.title)
                    .font(.display(28))
                    .foregroundStyle(Theme.ink)
                if let itinerary = trail.itineraryText {
                    Text(verbatim: itinerary)
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }

    @ViewBuilder
    private func facts(_ detail: TrailDetail) -> some View {
        let distance = Format.distanceParts(detail.length)
        let gain = elevationPoints.map { Geo.elevationGain(of: $0, threshold: 10) }
        let ascent = gain?.ascent ?? 0
        let descent = gain?.descent ?? 0

        HStack(alignment: .top, spacing: 0) {
            StatView(label: "Distance", value: distance.value, unit: distance.unit)
                .frame(maxWidth: .infinity, alignment: .leading)
            StatView(
                label: "Ascent",
                value: gain == nil ? "–" : Format.meters(ascent),
                unit: gain == nil ? "" : "m"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            StatView(
                label: "Est. time",
                value: Format.duration(Geo.hikingDuration(distance: detail.length, ascent: ascent, descent: descent))
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .hikeCard(padding: 16)

        if let elevationPoints {
            let samples = ElevationProfile.samples(for: elevationPoints)
            if samples.count > 2 {
                ElevationChart(samples: samples)
                    .frame(height: 130)
                    .hikeCard(padding: 16)
            }
        }

        VStack(alignment: .leading, spacing: 10) {
            if let network = trail.network {
                factRow(label: "Network", value: Text(network.title))
            }
            if let ref = detail.summary.ref, !ref.isEmpty {
                factRow(label: "Waymark", value: Text(verbatim: ref))
            }
            if let symbol = detail.summary.symbolDescription, !symbol.isEmpty {
                factRow(label: "Symbol", value: Text(verbatim: symbol))
            }
            if let name = detail.operatorName, !name.isEmpty {
                factRow(label: "Maintained by", value: Text(verbatim: name))
            }
            if let text = detail.summaryText, !text.isEmpty {
                factRow(label: "Route", value: Text(verbatim: text))
            }
            if let website = detail.website {
                Link(destination: website) {
                    Label("Website", systemImage: "arrow.up.right")
                        .font(.system(size: 15, weight: .semibold))
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hikeCard(padding: 16)

        if saved {
            Button("Show in My hikes") { appState.tab = .library }
                .buttonStyle(SecondaryButtonStyle())
        } else {
            Button("Save to My hikes") { save(detail) }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(detail.allPoints.count < 2)
        }

        Text("Trail data © OpenStreetMap contributors, via Waymarked Trails.")
            .font(.system(size: 12))
            .foregroundStyle(Theme.inkSoft)
    }

    private func factRow(label: LocalizedStringKey, value: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 110, alignment: .leading)
            value
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
        }
    }

    private func load() async {
        guard detail == nil else { return }
        do {
            let loaded = try await TrailService.detail(for: trail)
            detail = loaded
            if let box = Geo.boundingBox(of: loaded.allPoints) {
                focus = .box(box)
            }
            elevationPoints = await ElevationService.elevations(for: loaded.allPoints)
        } catch {
            loadFailed = true
        }
    }

    private func save(_ detail: TrailDetail) {
        // Prefer the points that carry elevation when the trail is short enough that
        // nothing was thinned out to fetch them.
        var points = detail.allPoints
        if let elevationPoints, elevationPoints.count == points.count {
            points = elevationPoints
        }
        let hike = SavedHike(name: trail.title, kind: .trail, points: points)
        modelContext.insert(hike)
        saved = true
    }
}
