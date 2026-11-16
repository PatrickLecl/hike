import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case plan
    case discover
    case record
    case library
}

/// A route shown on the Record screen so you can follow it while walking.
struct FollowedRoute: Equatable {
    var name: String
    var points: [GeoPoint]

    static func == (lhs: FollowedRoute, rhs: FollowedRoute) -> Bool {
        lhs.name == rhs.name && lhs.points.count == rhs.points.count && lhs.points.first == rhs.points.first
    }
}

/// State shared between the tabs.
final class AppState: ObservableObject {
    @Published var tab: AppTab = .plan
    @Published var followedRoute: FollowedRoute?
}

@main
struct HikeApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var tracker = LocationTracker()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(tracker)
                .tint(Theme.blaze)
        }
        .modelContainer(for: SavedHike.self)
    }
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @State private var importFailed = false

    var body: some View {
        TabView(selection: $appState.tab) {
            PlanView()
                .tabItem { Label("Plan", systemImage: "map") }
                .tag(AppTab.plan)
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "magnifyingglass") }
                .tag(AppTab.discover)
            RecordView()
                .tabItem { Label("Record", systemImage: "record.circle") }
                .tag(AppTab.record)
            LibraryView()
                .tabItem { Label("My hikes", systemImage: "bookmark") }
                .tag(AppTab.library)
        }
        // GPX files opened from Files, Mail or another app land in My hikes.
        .onOpenURL { url in
            importFile(at: url)
        }
        .alert("Could not open this file", isPresented: $importFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The file does not contain a route Hike can read.")
        }
    }

    private func importFile(at url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            try HikeImporter.importGPX(
                data, fallbackName: url.deletingPathExtension().lastPathComponent, into: modelContext
            )
            appState.tab = .library
        } catch {
            importFailed = true
        }
    }
}
