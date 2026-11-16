import SwiftData
import SwiftUI

/// A saved hike: map, statistics, elevation profile and actions.
struct HikeDetailView: View {
    @Bindable var hike: SavedHike

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var tracker: LocationTracker
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mapLayer") private var layerRaw = MapLayer.outdoor.rawValue

    @State private var points: [GeoPoint] = []
    @State private var waypoints: [GeoPoint] = []
    @State private var samples: [ElevationSample] = []
    @State private var focus: MapFocus?
    @State private var gpxURL: URL?
    @State private var downloadProgress: Double?
    @State private var downloadIncomplete = false
    @State private var showRename = false
    @State private var newName = ""
    @State private var showDeleteConfirmation = false

    private var layer: MapLayer { MapLayer(rawValue: layerRaw) ?? .outdoor }

    private var pins: [HikePin] {
        guard let first = points.first, let last = points.last else { return [] }
        if Geo.distance(first, last) < 30 {
            return [HikePin(id: "start", point: first, label: "A")]
        }
        return [
            HikePin(id: "start", point: first, label: "A"),
            HikePin(id: "end", point: last, label: "B"),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZStack(alignment: .bottomLeading) {
                    HikeMapView(
                        layer: layer,
                        lines: [MapLine(id: "hike", points: points, style: hike.kind == .recorded ? .recorded : .route)],
                        pins: pins,
                        showsUser: tracker.isAuthorized,
                        focus: focus
                    )
                    MapAttribution(layer: layer).padding(6)
                }
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: hike.name)
                        .font(.display(28))
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: 8) {
                        TagView(
                            text: hike.kind.title, systemImage: hike.kind.systemImage,
                            tint: Theme.inkSoft, background: Theme.line.opacity(0.5)
                        )
                        if hike.isOffline {
                            TagView(text: "Offline", systemImage: "arrow.down.circle")
                        }
                        Text(verbatim: Format.date(hike.createdAt))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }

                statistics

                if samples.count > 2 {
                    ElevationChart(samples: samples, tint: hike.kind == .recorded ? Theme.glacier : Theme.blaze)
                        .frame(height: 140)
                        .hikeCard(padding: 16)
                }

                actions
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.vertical, 12)
        }
        .background(Theme.paper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.paper, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        newName = hike.name
                        showRename = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(Text("More"))
            }
        }
        .task { await load() }
        .alert("Rename hike", isPresented: $showRename) {
            TextField("Name", text: $newName)
            Button("Save") {
                let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    hike.name = trimmed
                    gpxURL = HikeImporter.exportGPX(hike)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Some map tiles could not be downloaded", isPresented: $downloadIncomplete) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Parts of the map may be missing offline. Try again with a better connection.")
        }
        .confirmationDialog("Delete this hike?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                // Leave the screen first: it must not keep reading a hike that is gone.
                let target = hike
                let context = modelContext
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    context.delete(target)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var statistics: some View {
        let distance = Format.distanceParts(hike.distance)
        return VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 0) {
                StatView(label: "Distance", value: distance.value, unit: distance.unit)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StatView(
                    label: "Ascent",
                    value: hike.hasElevation ? Format.meters(hike.ascent) : "–",
                    unit: hike.hasElevation ? "m" : ""
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                StatView(
                    label: hike.kind == .recorded ? "Time" : "Est. time",
                    value: Format.duration(hike.duration)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if hike.hasElevation {
                HStack(alignment: .top, spacing: 0) {
                    StatView(label: "Descent", value: Format.meters(hike.descent), unit: "m", size: 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let highest = points.compactMap(\.elevation).max() {
                        StatView(label: "Highest point", value: Format.meters(highest), unit: "m", size: 18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer().frame(maxWidth: .infinity)
                }
            }
        }
        .hikeCard(padding: 16)
    }

    @ViewBuilder
    private var actions: some View {
        if hike.kind != .recorded {
            Button("Start this hike") {
                appState.followedRoute = FollowedRoute(name: hike.name, points: points)
                appState.tab = .record
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(points.count < 2)
        }

        if let downloadProgress {
            VStack(alignment: .leading, spacing: 8) {
                Text("Downloading map…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.ink)
                ProgressView(value: downloadProgress)
                    .tint(Theme.blaze)
            }
            .hikeCard(padding: 16)
        } else if !hike.isOffline {
            Button {
                Task { await downloadMap() }
            } label: {
                Label("Save map for offline use", systemImage: "arrow.down.circle")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(points.count < 2)
        }

        if let gpxURL {
            ShareLink(item: gpxURL) {
                Label("Share as GPX", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    // MARK: Actions

    private func load() async {
        guard points.isEmpty else { return }
        points = hike.points
        waypoints = hike.waypoints
        samples = ElevationProfile.samples(for: points)
        if let box = Geo.boundingBox(of: points) {
            focus = .box(box)
        }
        gpxURL = HikeImporter.exportGPX(hike)

        // Imported files and saved trails often lack elevation; add it when possible.
        if !hike.hasElevation, ElevationService.isAvailable,
           points.count <= OpenRouteService.elevationPointLimit,
           let enriched = await ElevationService.elevations(for: points), enriched.count == points.count {
            guard hike.modelContext != nil, !hike.isDeleted else { return }
            points = enriched
            samples = ElevationProfile.samples(for: enriched)
            hike.updatePoints(enriched)
            gpxURL = HikeImporter.exportGPX(hike)
        }
    }

    private func downloadMap() async {
        let tiles = TileStore.shared.offlineTiles(for: points)
        guard !tiles.isEmpty else { return }
        downloadProgress = 0
        let failed = await TileStore.shared.download(tiles) { finished, total in
            downloadProgress = Double(finished) / Double(max(total, 1))
        }
        downloadProgress = nil
        // The hike may have been deleted while the tiles were downloading.
        guard hike.modelContext != nil, !hike.isDeleted else { return }
        // A handful of missing tiles is tolerable; more means the map has real gaps.
        if failed > tiles.count / 20 {
            downloadIncomplete = true
        } else {
            hike.isOffline = true
        }
    }
}
