import Foundation

/// 离线矢量底图样式（任务 2.2）：为 planetiler 生成的 OpenMapTiles schema PMTiles 生成一份
/// 紧凑 MapLibre style JSON（仅几何，不含文字/symbol → 无需字体 glyphs），指向本地 `pmtiles://`。
enum OfflineVectorStyle {

    /// 由本地 .pmtiles 路径生成样式文件，返回 styleURL。
    static func styleURL(pmtilesPath: String) -> URL {
        // 用标准 file:// 绝对 URL（中文等会被正确百分号编码），再加 pmtiles:// 前缀
        let fileURL = URL(fileURLWithPath: pmtilesPath)
        let source = "pmtiles://\(fileURL.absoluteString)"
        let style: [String: Any] = [
            "version": 8,
            "name": "offline-vector",
            "sources": ["v": ["type": "vector", "url": source]],
            "layers": layers()
        ]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-style-\(UInt(bitPattern: pmtilesPath.hashValue)).json")
        if let data = try? JSONSerialization.data(withJSONObject: style) {
            try? data.write(to: url)
        }
        return url
    }

    // 绘制顺序：底色 → 地表 → 用地 → 公园 → 水 → 水系 → 道路 → 步道 → 建筑 → 边界
    private static func layers() -> [[String: Any]] {
        func fill(_ id: String, _ srcLayer: String, _ color: String, _ opacity: Double) -> [String: Any] {
            ["id": id, "type": "fill", "source": "v", "source-layer": srcLayer,
             "paint": ["fill-color": color, "fill-opacity": opacity]]
        }
        let roadWidth: [Any] = ["interpolate", ["linear"], ["zoom"], 10, 0.5, 13, 1.5, 16, 4.0]
        return [
            ["id": "bg", "type": "background", "paint": ["background-color": "#EDE7DD"]],
            fill("landcover", "landcover", "#D6E6C8", 0.6),
            fill("landuse", "landuse", "#E6E0D4", 0.4),
            fill("park", "park", "#D8E8C8", 0.5),
            fill("water", "water", "#9FC6E8", 1.0),
            ["id": "waterway", "type": "line", "source": "v", "source-layer": "waterway",
             "paint": ["line-color": "#9FC6E8", "line-width": 1.2]],
            // 道路（全部 transportation，浅灰）
            ["id": "roads", "type": "line", "source": "v", "source-layer": "transportation",
             "paint": ["line-color": "#FAF8F4", "line-width": roadWidth]],
            // 步道/小径（棕色虚线，叠在道路之上）
            ["id": "paths", "type": "line", "source": "v", "source-layer": "transportation",
             "filter": ["in", "class", "path", "track", "footway", "cycleway"],
             "paint": ["line-color": "#A0673B", "line-width": 1.4, "line-dasharray": [2.0, 1.5]]],
            fill("building", "building", "#D9CFC2", 0.7),
            ["id": "boundary", "type": "line", "source": "v", "source-layer": "boundary",
             "paint": ["line-color": "#9A8FB0", "line-width": 0.8, "line-dasharray": [3.0, 2.0]]]
        ]
    }
}
