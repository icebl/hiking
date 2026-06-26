import Foundation

/// 离线栅格底图样式（任务 2.7 / S2-B）：为下载的 MBTiles 卫星瓦片生成 MapLibre style，指向本地 `mbtiles://`。
enum OfflineRasterStyle {
    static func styleURL(mbtilesPath: String) -> URL {
        let fileURL = URL(fileURLWithPath: mbtilesPath)
        let source = "mbtiles://\(fileURL.absoluteString)"
        let style: [String: Any] = [
            "version": 8,
            "name": "offline-raster",
            "sources": ["r": ["type": "raster", "url": source, "tileSize": 256]],
            "layers": [["id": "r", "type": "raster", "source": "r"]]
        ]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-raster-\(UInt(bitPattern: mbtilesPath.hashValue)).json")
        if let data = try? JSONSerialization.data(withJSONObject: style) {
            try? data.write(to: url)
        }
        return url
    }
}
