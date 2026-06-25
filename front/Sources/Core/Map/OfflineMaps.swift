import Foundation

/// 底图模式：在线栅格（ESRI）/ 离线矢量（本地 PMTiles 文件）。
enum MapBaseMode: Equatable {
    case onlineRaster
    case offlineVector(path: String)
}

/// 离线包管理（任务 2.7 / A 段）：Documents/offline/*.pmtiles 的导入、列举、删除。
enum OfflineMaps {
    static var dir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("offline", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// 已导入的 .pmtiles 列表。
    static func list() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return items.filter { $0.pathExtension.lowercased() == "pmtiles" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
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

    static func delete(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    static func sizeMB(_ url: URL) -> Double {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Double(bytes) / 1024 / 1024
    }
}
