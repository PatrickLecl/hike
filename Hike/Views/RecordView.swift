import SwiftData
import SwiftUI
import UIKit

/// Records a hike with GPS. Always dark, with large numbers that can be read at a glance
/// in bright daylight.
struct RecordView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var tracker: LocationTracker
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @AppStorage("mapLayer") private var layerRaw = MapLayer.outdoor.rawValue

    @State private var focus: MapFocus?
    @State private var showFinishPrompt = false
    @State private var showDiscardConfirmation = false
    @State private var hikeName = ""

    private var layer: MapLayer { MapLayer(rawValue: layerRaw) ?? .outdoor }

    private var lines: [MapLine] {
        var result: [MapLine] = []
        if let followed = appState.followedRoute {
            result.append(MapLine(id: "followed", points: followed.points, style: .route))
        }
        if tracker.points.count >= 2 {
            result.append(MapLine(id: "recorded", points: tracker.points, style: .recorded))
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                HikeMapView(layer: layer, lines: lines, showsUser: tracker.isAuthorized, focus: focus)
                    .ignoresSafeArea(edges: .top)
                mapOverlay
            }
            .frame(maxHeight: .infinity)

            controls
        }
        .background(Theme.spruce)
        .toolbarBackground(Theme.spruce, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .onAppear {
            tracker.startUpdating()
            if let followed = appState.followedRoute, tracker.state == .idle,
               let box = Geo.boundingBox(of: followed.points) {
                focus = .box(box)
            } else if tracker.isAuthorized {
                focus = .user
            }
        }
        .onChange(of: appState.followedRoute) { _, followed in
            if let followed, let box = Geo.boundingBox(of: followed.points) {
                focus = .box(box)
            }
        }
        .alert("Save this hike", isPresented: $showFinishPrompt) {
            TextField("Name", text: $hikeName)
            Button("Save") { finish(save: true) }
            Button("Keep recording", role: .cancel) {}
        } message: {
            Text("Give your hike a name to find it back in My hikes.")
        }
        .confirmationDialog(
            "Discard this recording?", isPresented: $showDiscardConfirmation, titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { finish(save: false) }
            Button("Keep recording", role: .cancel) {}
        }
    }

    // MARK: Map overlay

    private var mapOverlay: some View {
        HStack(alignment: .top) {
            if let followed = appState.followedRoute {
                HStack(spacing: 8) {
                    BlazeMark(width: 22)
                    Text(verbatim: followed.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.chalk)
                        .lineLimit(1)
                    if tracker.state == .idle {
                        Button {
                            appState.followedRoute = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.chalkSoft)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Stop following this route"))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.spruce.opacity(0.92), in: Capsule())
            }
            Spacer()
            Button {
                if tracker.isAuthorized { focus = .user } else { tracker.startUpdating() }
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.chalk)
                    .frame(width: 44, height: 44)
                    .background(Theme.spruce.opacity(0.92), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("My location"))
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    // MARK: Statistics and controls

    private var controls: some View {
        VStack(spacing: 18) {
            if tracker.isDenied {
                permissionDenied
            } else {
                statistics
                buttons
            }
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(Theme.spruce)
    }

    private var statistics: some View {
        let distance = Format.distanceParts(tracker.distance)
        return VStack(alignment: .leading, spacing: 12) {
            StatView(
                label: "Distance", value: distance.value, unit: distance.unit, size: 54,
                primary: Theme.chalk, secondary: Theme.chalkSoft
            )
            Divider().overlay(Theme.spruceRaised)
            HStack(alignment: .top, spacing: 0) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    StatView(
                        label: "Time", value: Format.stopwatch(tracker.elapsed(at: context.date)), size: 34,
                        primary: Theme.chalk, secondary: Theme.chalkSoft
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StatView(
                    label: "Total ascent", value: Format.meters(tracker.ascent), unit: "m", size: 34,
                    primary: Theme.chalk, secondary: Theme.chalkSoft
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var buttons: some View {
        switch tracker.state {
        case .idle:
            Button {
                start()
            } label: {
                Text("Start hike")
                    .font(.display(18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.blaze, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        case .recording:
            Button {
                tracker.pauseRecording()
            } label: {
                Image(systemName: "pause.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(Theme.blaze, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Pause"))
        case .paused:
            HStack(spacing: 12) {
                Button {
                    tracker.resumeRecording()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.blaze, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Button {
                    if tracker.points.count >= 2 {
                        hikeName = appState.followedRoute?.name ?? ""
                        showFinishPrompt = true
                    } else {
                        showDiscardConfirmation = true
                    }
                } label: {
                    Label("Finish", systemImage: "flag.checkered")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.chalk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.spruceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .buttonStyle(.plain)
            if tracker.points.count >= 2 {
                Button("Discard recording") { showDiscardConfirmation = true }
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.chalkSoft)
                    .buttonStyle(.plain)
            }
        }
    }

    private var permissionDenied: some View {
        VStack(spacing: 12) {
            Text("Location access is off")
                .font(.display(22))
                .foregroundStyle(Theme.chalk)
            Text("Hike needs your location to record a hike. You can allow it in Settings.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.chalkSoft)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.blaze)
            .padding(.top, 4)
        }
        .padding(.vertical, 10)
    }

    // MARK: Actions

    private func start() {
        guard tracker.isAuthorized else {
            tracker.requestPermission()
            return
        }
        tracker.startRecording()
        focus = .user
    }

    private func finish(save: Bool) {
        let recording = tracker.finishRecording()
        guard save, recording.points.count >= 2 else { return }
        let trimmed = hikeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty
            ? String(localized: "Hike") + " " + Format.date(Date())
            : trimmed
        let hike = SavedHike(
            name: name, kind: .recorded, points: recording.points, walkedDuration: recording.duration
        )
        modelContext.insert(hike)
        appState.followedRoute = nil
        appState.tab = .library
    }
}
