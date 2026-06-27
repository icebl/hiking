import Foundation

/// 离线栅格底图样式（任务 2.7 / S2-B）：为下载的 MBTiles 卫星瓦片生成 MapLibre style，指向本地 `mbtiles://`。
enum OfflineRasterStyle {
    /// 由本地 .mbtiles 路径生成栅格样式文件，返回 styleURL。
    static func styleURL(mbtilesPath: String) -> URL {
        let fileURL = URL(fileURLWithPath: mbtilesPath)   // 正确百分号编码（含中文路径）
        let source = "mbtiles://\(fileURL.absoluteString)"
        let style: [String: Any] = [
            "version": 8,
            "name": "offline-raster",
            // tileSize 256：ESRI/常规栅格瓦片标准尺寸
            "sources": ["r": ["type": "raster", "url": source, "tileSize": 256]],
            "layers": [["id": "r", "type": "raster", "source": "r"]]
        ]
        // 文件名按路径 hash 去重：同一包复用同一临时文件，不同包互不覆盖
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-raster-\(UInt(bitPattern: mbtilesPath.hashValue)).json")
        if let data = try? JSONSerialization.data(withJSONObject: style) {
            try? data.write(to: url)
        }
        return url
    }
}
