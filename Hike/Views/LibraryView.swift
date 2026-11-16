import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// GPX, declared as an imported type in Info.plist.
    static let gpx = UTType(importedAs: "com.topografix.gpx")
}

extension HikeKind {
    var title: LocalizedStringKey {
        switch self {
        case .planned: return "Planned"
        case .recorded: return "Recorded"
        case .imported: return "Imported"
        case .trail: return "Trail"
        }
    }

    var systemImage: String {
        switch self {
        case .planned: return "pencil.and.outline"
        case .recorded: return "record.circle"
        case .imported: return "square.and.arrow.down"
        case .trail: return "signpost.right"
        }
    }
}

/// "My hikes": everything planned, recorded, imported or saved from a trail.
struct LibraryView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedHike.createdAt, order: .reverse) private var hikes: [SavedHike]

    @State private var showImporter = false
    @State private var showSettings = false
    @State private var importFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        ScreenTitle(text: "My hikes")
                        Button {
                            showImporter = true
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .accessibilityLabel(Text("Import GPX file"))
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel(Text("Settings"))
                        .padding(.leading, 10)
                    }
                    .font(.system(size: 20, weight: .medium))
                    .tint(Theme.ink)

                    if hikes.isEmpty {
                        EmptyStateView(
                            title: "No hikes yet",
                            message: "Plan a route, save a trail from Discover or import a GPX file."
                        )
                        .padding(.top, 40)
                        Button("Plan a hike") { appState.tab = .plan }
                            .buttonStyle(PrimaryButtonStyle())
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(hikes) { hike in
                                NavigationLink(value: hike.id) {
                                    HikeRow(hike: hike)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        modelContext.delete(hike)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.paper)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let hike = hikes.first(where: { $0.id == id }) {
                    HikeDetailView(hike: hike)
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.gpx, .xml]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                try HikeImporter.importGPX(
                    data, fallbackName: url.deletingPathExtension().lastPathComponent, into: modelContext
                )
            } catch {
                importFailed = true
            }
        }
        .alert("Could not open this file", isPresented: $importFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The file does not contain a route Hike can read.")
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

/// One saved hike in the list.
struct HikeRow: View {
    var hike: SavedHike

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RouteThumbnail(points: hike.previewPoints, seed: Int(hike.createdAt.timeIntervalSince1970) % 97)
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: hike.name)
                    .font(.display(18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Text(verbatim: Format.date(hike.createdAt))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
                HStack(spacing: 12) {
                    Label {
                        Text(verbatim: Format.distance(hike.distance))
                    } icon: {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    if hike.hasElevation {
                        Label {
                            Text(verbatim: Format.elevation(hike.ascent))
                        } icon: {
                            Image(systemName: "arrow.up.right")
                        }
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
                .labelStyle(.titleAndIcon)
                HStack(spacing: 6) {
                    TagView(
                        text: hike.kind.title, systemImage: hike.kind.systemImage,
                        tint: Theme.inkSoft, background: Theme.line.opacity(0.5)
                    )
                    if hike.isOffline {
                        TagView(text: "Offline", systemImage: "arrow.down.circle")
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
        }
        .hikeCard(padding: 12)
        .contentShape(Rectangle())
    }
}
