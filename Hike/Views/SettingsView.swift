import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("mapLayer") private var layerRaw = MapLayer.outdoor.rawValue
    @Query private var hikes: [SavedHike]

    @State private var storageText = "–"
    @State private var showClearConfirmation = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Map") {
                    Picker("Map style", selection: $layerRaw) {
                        Text("Topographic").tag(MapLayer.outdoor.rawValue)
                        Text("Standard").tag(MapLayer.standard.rawValue)
                        Text("Satellite").tag(MapLayer.satellite.rawValue)
                    }
                }

                Section {
                    LabeledContent("Stored map data") {
                        Text(verbatim: storageText)
                    }
                    Button("Delete offline maps", role: .destructive) {
                        showClearConfirmation = true
                    }
                } header: {
                    Text("Offline")
                } footer: {
                    Text("Maps you have viewed and maps saved with a hike are kept on this iPhone.")
                }

                Section {
                    LabeledContent("Route planning") {
                        if AppConfig.openRouteServiceKey == nil {
                            Text("Apple Maps")
                        } else {
                            Text(verbatim: "openrouteservice")
                        }
                    }
                } header: {
                    Text("Routing")
                } footer: {
                    if AppConfig.openRouteServiceKey == nil {
                        Text("Routes follow walking directions from Apple Maps and have no elevation data.")
                    } else {
                        Text("Routes follow hiking paths and include elevation.")
                    }
                }

                Section {
                    Link("OpenStreetMap", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                    Link("OpenTopoMap", destination: URL(string: "https://opentopomap.org/about")!)
                    Link("Waymarked Trails", destination: URL(string: "https://hiking.waymarkedtrails.org")!)
                    Link("openrouteservice", destination: URL(string: "https://openrouteservice.org")!)
                } header: {
                    Text("Map and trail data")
                } footer: {
                    Text("Maps, trails and routes are built on OpenStreetMap, made by volunteers around the world.")
                }

                Section {
                    LabeledContent("Version") {
                        Text(verbatim: version)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await refreshStorage() }
            .confirmationDialog(
                "Delete all offline maps?", isPresented: $showClearConfirmation, titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { clearStorage() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your hikes are kept. Maps are downloaded again when you are online.")
            }
        }
        .tint(Theme.blaze)
    }

    private func refreshStorage() async {
        let bytes = await Task.detached { TileStore.shared.sizeOnDisk() }.value
        storageText = Format.fileSize(bytes)
    }

    private func clearStorage() {
        TileStore.shared.removeAll()
        for hike in hikes where hike.isOffline {
            hike.isOffline = false
        }
        storageText = Format.fileSize(0)
    }
}
