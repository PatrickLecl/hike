import Foundation
import MapKit

/// Keeps topographic map tiles on disk so they load instantly and work without a connection.
final class TileStore {
    static let shared = TileStore()

    private let directory: URL
    private let session: URLSession

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        var folder = base.appendingPathComponent("Tiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Tiles can be downloaded again, so keep them out of iCloud backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        directory = folder

        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["User-Agent": AppConfig.userAgent]
        configuration.timeoutIntervalForRequest = 20
        configuration.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: configuration)
    }

    private func fileURL(for tile: TileCoordinate) -> URL {
        directory
            .appendingPathComponent(String(tile.z), isDirectory: true)
            .appendingPathComponent(String(tile.x), isDirectory: true)
            .appendingPathComponent("\(tile.y).png")
    }

    func cachedData(for tile: TileCoordinate) -> Data? {
        try? Data(contentsOf: fileURL(for: tile))
    }

    func hasTile(_ tile: TileCoordinate) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: tile).path)
    }

    private func store(_ data: Data, for tile: TileCoordinate) {
        let url = fileURL(for: tile)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Returns the tile from disk, or downloads and stores it.
    func data(for tile: TileCoordinate) async throws -> Data {
        if let cached = cachedData(for: tile) { return cached }
        guard let url = TileMath.url(template: AppConfig.outdoorTileTemplate, tile: tile) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: url)
        // Only keep real images: a Wi-Fi login page also answers with status 200.
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty,
              http.mimeType?.hasPrefix("image/") == true
        else {
            throw URLError(.badServerResponse)
        }
        store(data, for: tile)
        return data
    }

    /// The tiles needed to show a route offline, capped so very long routes stay reasonable.
    func offlineTiles(for points: [GeoPoint]) -> [TileCoordinate] {
        var zooms = AppConfig.offlineZooms
        var tiles = TileMath.tiles(along: points, zooms: zooms)
        while tiles.count > AppConfig.offlineTileLimit, zooms.upperBound > zooms.lowerBound {
            zooms = zooms.lowerBound...(zooms.upperBound - 1)
            tiles = TileMath.tiles(along: points, zooms: zooms)
        }
        return tiles.sorted { ($0.z, $0.x, $0.y) < ($1.z, $1.x, $1.y) }
    }

    /// Downloads every missing tile. Reports progress as (finished, total) and returns how
    /// many tiles could not be fetched.
    func download(_ tiles: [TileCoordinate], progress: @escaping @MainActor (Int, Int) -> Void) async -> Int {
        let total = tiles.count
        var finished = 0
        var failed = 0
        var index = 0
        let batchSize = 4
        while index < tiles.count {
            if Task.isCancelled { break }
            let batch = Array(tiles[index..<min(index + batchSize, tiles.count)])
            let failures = await withTaskGroup(of: Bool.self) { group -> Int in
                for tile in batch {
                    group.addTask {
                        do {
                            _ = try await self.data(for: tile)
                            return true
                        } catch {
                            return false
                        }
                    }
                }
                var count = 0
                for await succeeded in group where !succeeded { count += 1 }
                return count
            }
            failed += failures
            finished += batch.count
            index += batchSize
            let done = finished
            await progress(done, total)
        }
        return failed + (total - finished)
    }

    /// Bytes used by stored tiles.
    func sizeOnDisk() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    func removeAll() {
        // Empty the folder rather than replacing it, so it stays excluded from backups.
        let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for item in items {
            try? FileManager.default.removeItem(at: item)
        }
    }
}

/// Map overlay that serves tiles through `TileStore`.
final class CachedTileOverlay: MKTileOverlay {
    init() {
        super.init(urlTemplate: AppConfig.outdoorTileTemplate)
        canReplaceMapContent = true
        maximumZ = AppConfig.outdoorTileMaxZoom
        tileSize = CGSize(width: 256, height: 256)
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let tile = TileCoordinate(x: path.x, y: path.y, z: path.z)
        Task.detached(priority: .userInitiated) {
            do {
                let data = try await TileStore.shared.data(for: tile)
                result(data, nil)
            } catch {
                result(nil, error)
            }
        }
    }
}
