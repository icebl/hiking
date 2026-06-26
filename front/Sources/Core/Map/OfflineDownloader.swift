import Foundation
import GRDB

/// 下载区域（地理范围 + 缩放范围）。
struct TileRegion {
    var minLon: Double, minLat: Double, maxLon: Double, maxLat: Double
    var minZoom: Int, maxZoom: Int
}

/// 框选区域离线下载（任务 2.7 / S2-B）：拉 ESRI 卫星栅格瓦片 → 写本地 MBTiles。
final class OfflineDownloader: ObservableObject {
    enum Phase: Equatable { case idle, downloading, finished, cancelled, failed }
    @Published var phase: Phase = .idle
    @Published var total = 0
    @Published var done = 0
    @Published var failed = 0

    private var cancelled = false
    // ESRI 世界影像（z/y/x 顺序）
    private let urlTemplate = "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"

    // MARK: - 瓦片数学（Web Mercator）
    static func tileX(_ lon: Double, _ z: Int) -> Int {
        let n = pow(2.0, Double(z))
        return min(Int(n) - 1, max(0, Int(floor((lon + 180) / 360 * n))))
    }
    static func tileY(_ lat: Double, _ z: Int) -> Int {
        let n = pow(2.0, Double(z))
        let r = lat * .pi / 180
        let y = (1 - log(tan(r) + 1 / cos(r)) / .pi) / 2 * n
        return min(Int(n) - 1, max(0, Int(floor(y))))
    }

    /// 区域内总瓦片数（各级求和）。
    static func tileCount(_ region: TileRegion) -> Int {
        guard region.maxZoom >= region.minZoom else { return 0 }
        var c = 0
        for z in region.minZoom...region.maxZoom {
            let x0 = tileX(region.minLon, z), x1 = tileX(region.maxLon, z)
            let y0 = tileY(region.maxLat, z), y1 = tileY(region.minLat, z)  // maxLat → 较小 y
            c += (abs(x1 - x0) + 1) * (abs(y1 - y0) + 1)
        }
        return c
    }

    /// 估算体积（MB），按卫星 jpg 约 20KB/瓦片。
    static func estimateMB(_ region: TileRegion) -> Double { Double(tileCount(region)) * 20 / 1024 }

    // MARK: - 下载
    func cancel() { cancelled = true }

    func start(region: TileRegion, dest: URL, name: String) {
        cancelled = false
        Task.detached { [weak self] in await self?.run(region: region, dest: dest, name: name) }
    }

    private func run(region: TileRegion, dest: URL, name: String) async {
        // 枚举瓦片
        var tiles: [(z: Int, x: Int, y: Int)] = []
        for z in region.minZoom...region.maxZoom {
            let x0 = Self.tileX(region.minLon, z), x1 = Self.tileX(region.maxLon, z)
            let y0 = Self.tileY(region.maxLat, z), y1 = Self.tileY(region.minLat, z)
            for x in min(x0, x1)...max(x0, x1) {
                for y in min(y0, y1)...max(y0, y1) { tiles.append((z, x, y)) }
            }
        }
        await publish { self.total = tiles.count; self.done = 0; self.failed = 0; self.phase = .downloading }

        // 打开/初始化 MBTiles
        guard let dbq = try? DatabaseQueue(path: dest.path) else {
            await publish { self.phase = .failed }; return
        }
        do { try initSchema(dbq, region: region, name: name) }
        catch { await publish { self.phase = .failed }; return }

        // 分块并发下载（每块 maxConcurrent 并发，块间屏障）+ 批量写库
        var pending: [(Int, Int, Int, Data)] = []
        var doneCount = 0, failCount = 0
        let maxConcurrent = 6
        let tmpl = urlTemplate
        var i = 0
        while i < tiles.count {
            if cancelled { break }
            let chunk = Array(tiles[i..<min(i + maxConcurrent, tiles.count)])
            let results = await withTaskGroup(of: (Int, Int, Int, Data?).self) { group -> [(Int, Int, Int, Data?)] in
                for t in chunk { group.addTask { (t.z, t.x, t.y, await Self.fetch(tmpl, t.z, t.x, t.y)) } }
                var acc: [(Int, Int, Int, Data?)] = []
                for await r in group { acc.append(r) }
                return acc
            }
            for (z, x, y, d) in results {
                if let d { pending.append((z, x, y, d)); doneCount += 1 } else { failCount += 1 }
            }
            if pending.count >= 80 { try? flush(dbq, &pending) }
            let dc = doneCount, fc = failCount
            await publish { self.done = dc; self.failed = fc }
            i += maxConcurrent
        }
        try? flush(dbq, &pending)
        let dc = doneCount, fc = failCount, wasCancelled = cancelled
        await publish {
            self.done = dc; self.failed = fc
            self.phase = wasCancelled ? .cancelled : .finished
        }
    }

    private static func fetch(_ template: String, _ z: Int, _ x: Int, _ y: Int) async -> Data? {
        let s = template.replacingOccurrences(of: "{z}", with: "\(z)")
            .replacingOccurrences(of: "{y}", with: "\(y)")
            .replacingOccurrences(of: "{x}", with: "\(x)")
        guard let url = URL(string: s) else { return nil }
        for _ in 0..<2 {   // 重试一次
            if let (data, resp) = try? await URLSession.shared.data(from: url),
               (resp as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty {
                return data
            }
        }
        return nil
    }

    private func initSchema(_ dbq: DatabaseQueue, region: TileRegion, name: String) throws {
        try dbq.write { db in
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS metadata(name TEXT, value TEXT)")
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS tiles(
                  zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB,
                  PRIMARY KEY(zoom_level, tile_column, tile_row))
                """)
            let meta: [(String, String)] = [
                ("name", name), ("format", "jpg"), ("type", "baselayer"), ("version", "1.0"),
                ("minzoom", "\(region.minZoom)"), ("maxzoom", "\(region.maxZoom)"),
                ("bounds", "\(region.minLon),\(region.minLat),\(region.maxLon),\(region.maxLat)")
            ]
            for (k, v) in meta {
                try db.execute(sql: "INSERT INTO metadata(name,value) VALUES(?,?)", arguments: [k, v])
            }
        }
    }

    private func flush(_ dbq: DatabaseQueue, _ pending: inout [(Int, Int, Int, Data)]) throws {
        guard !pending.isEmpty else { return }
        let batch = pending; pending.removeAll(keepingCapacity: true)
        try dbq.write { db in
            for (z, x, y, data) in batch {
                let tmsY = (1 << z) - 1 - y          // MBTiles 用 TMS 翻转的 y
                try db.execute(sql: "INSERT OR REPLACE INTO tiles(zoom_level,tile_column,tile_row,tile_data) VALUES(?,?,?,?)",
                               arguments: [z, x, tmsY, data])
            }
        }
    }

    @MainActor private func publish(_ block: @escaping () -> Void) { block() }
}
