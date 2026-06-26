import Foundation

/// 底图模式：在线栅格（ESRI）/ 离线矢量（本地 PMTiles）/ 离线影像（本地 MBTiles 栅格）。
enum MapBaseMode: Equatable {
    case onlineRaster
    case offlineVector(path: String)
    case offlineRaster(path: String)
}

/// 离线包管理（任务 2.7 / A 段）：Documents/offline/*.pmtiles 的导入、列举、删除。
enum OfflineMaps {
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
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        let dest = dir.appendingPathComponent(src.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
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
}
