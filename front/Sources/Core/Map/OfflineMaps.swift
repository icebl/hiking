import Foundation
import CoreLocation
import GRDB

/// 在线栅格底图源（ESRI ArcGIS，免 key、国内可达）：卫星影像 / 地形图 / 街道图。
enum OnlineBaseSource: String, CaseIterable, Equatable {
    case satellite, topo, street

    var label: String {
        switch self {
        case .satellite: return "在线影像"
        case .topo:      return "地形图"
        case .street:    return "街道图"
        }
    }
    /// ArcGIS 瓦片模板（{z}/{y}/{x}）。
    var urlTemplate: String {
        let base = "https://server.arcgisonline.com/ArcGIS/rest/services"
        switch self {
        case .satellite: return "\(base)/World_Imagery/MapServer/tile/{z}/{y}/{x}"
        case .topo:      return "\(base)/World_Topo_Map/MapServer/tile/{z}/{y}/{x}"
        case .street:    return "\(base)/World_Street_Map/MapServer/tile/{z}/{y}/{x}"
        }
    }
    /// 最高级别（超过则过缩放，避免请求到无数据灰瓦片）：影像深，地形国内略浅。
    var maxZoom: Int {
        switch self {
        case .satellite: return 18
        case .topo:      return 17
        case .street:    return 18
        }
    }
}

/// 底图模式：在线栅格（ESRI，带源）/ 离线矢量（本地 PMTiles）/ 离线影像（本地 MBTiles 栅格）。
enum MapBaseMode: Equatable {
    case onlineRaster(OnlineBaseSource)
    case offlineVector(path: String)
    case offlineRaster(path: String)
}

/// 离线包管理（任务 2.7 / A 段）：Documents/offline/*.pmtiles 的导入、列举、删除。
enum OfflineMaps {
    /// 离线包根目录 Documents/offline；读取时顺带确保目录存在。
    static var dir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("offline", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// 已导入/生成的离线包（.pmtiles 矢量 + .mbtiles 栅格）。
    static func list() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return items.filter { ["pmtiles", "mbtiles"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func isRaster(_ url: URL) -> Bool { url.pathExtension.lowercased() == "mbtiles" }
    /// 矢量底图包：.pmtiles 且非等高线。
    static func isVectorBase(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "pmtiles" && !isContour(url)
    }

    /// 导入（拷贝到 offline 目录），返回目标 URL。
    @discardableResult
    static func importPack(from src: URL) throws -> URL {
        // 文件选择器返回的 URL 受沙盒保护，访问前后须成对开/关安全作用域
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        let dest = dir.appendingPathComponent(src.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {   // 同名先删，实现覆盖导入
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: src, to: dest)
        return dest
    }

    /// 文件名含 "contour" 视为等高线包。
    static func isContour(_ url: URL) -> Bool {
        url.lastPathComponent.lowercased().contains("contour")
    }
    /// 第一个等高线包（开等高线时用）。
    static func contourPack() -> URL? { list().first(where: isContour) }

    static func delete(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    static func sizeMB(_ url: URL) -> Double {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Double(bytes) / 1024 / 1024
    }

    /// 读取离线影像(MBTiles)的覆盖范围（metadata.bounds: minLon,minLat,maxLon,maxLat）。
    static func bounds(of url: URL) -> (sw: CLLocationCoordinate2D, ne: CLLocationCoordinate2D)? {
        guard isRaster(url), let dbq = try? DatabaseQueue(path: url.path) else { return nil }
        let str = (try? dbq.read { db -> String? in
            try String.fetchOne(db, sql: "SELECT value FROM metadata WHERE name = 'bounds'")
        }) ?? nil
        guard let str else { return nil }
        let p = str.split(separator: ",").compactMap { Double($0) }
        guard p.count == 4 else { return nil }
        // metadata.bounds 顺序为 minLon,minLat,maxLon,maxLat → 组装西南/东北角
        return (CLLocationCoordinate2D(latitude: p[1], longitude: p[0]),   // SW
                CLLocationCoordinate2D(latitude: p[3], longitude: p[2]))   // NE
    }
}
