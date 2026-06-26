import Foundation

/// 离线矢量底图样式（任务 2.2 + 路名标注/路网）：为 planetiler 生成的 OpenMapTiles schema PMTiles
/// 生成一份 MapLibre style JSON，指向本地 `pmtiles://`。
/// 含：几何层 + 文字标注层（需 glyphs 字体）+ 可开关的醒目路网层。
enum OfflineVectorStyle {

    /// 由本地 .pmtiles 路径生成样式文件，返回 styleURL。
    static func styleURL(pmtilesPath: String) -> URL {
        // 用标准 file:// 绝对 URL（中文等会被正确百分号编码），再加 pmtiles:// 前缀
        let fileURL = URL(fileURLWithPath: pmtilesPath)
        let source = "pmtiles://\(fileURL.absoluteString)"
        var style: [String: Any] = [
            "version": 8,
            "name": "offline-vector",
            "sources": ["v": ["type": "vector", "url": source]],
            "layers": layers()
        ]
        // glyphs：指向 App bundle 内 Resources/glyphs/{fontstack}/{range}.pbf
        // 拉丁字形已打包；中文(CJK)由 MapLibre Native iOS 用系统字体本地栅格化。
        if let glyphs = glyphsTemplate() { style["glyphs"] = glyphs }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-style-\(UInt(bitPattern: pmtilesPath.hashValue)).json")
        if let data = try? JSONSerialization.data(withJSONObject: style) {
            try? data.write(to: url)
        }
        return url
    }

    /// bundle 内 glyphs 目录的 file:// 模板（含 {fontstack}/{range} 占位）。
    private static func glyphsTemplate() -> String? {
        // Resources/glyphs 在 XcodeGen 的 Resources 源里 → 复制进 bundle 根。
        guard let dir = Bundle.main.url(forResource: "glyphs", withExtension: nil) else { return nil }
        // file:///.../glyphs/{fontstack}/{range}.pbf （确保目录后带 "/"）
        var base = dir.absoluteString
        if !base.hasSuffix("/") { base += "/" }
        return base + "{fontstack}/{range}.pbf"
    }

    private static let fontStack: [Any] = ["OpenSans"]

    // 绘制顺序：底色 → 地表 → 用地 → 公园 → 水 → 水系 → 道路 → 步道 → 路网(可开关) → 建筑 → 边界 → 各类标注
    private static func layers() -> [[String: Any]] {
        func fill(_ id: String, _ srcLayer: String, _ color: String, _ opacity: Double) -> [String: Any] {
            ["id": id, "type": "fill", "source": "v", "source-layer": srcLayer,
             "paint": ["fill-color": color, "fill-opacity": opacity]]
        }
        let roadWidth: [Any] = ["interpolate", ["linear"], ["zoom"], 10, 0.5, 13, 1.5, 16, 4.0]
        // 路网醒目橙线宽度（比普通步道更粗）
        let netWidth: [Any] = ["interpolate", ["linear"], ["zoom"], 11, 1.5, 14, 3.0, 17, 6.0]

        var ls: [[String: Any]] = [
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
            // 路网图层（醒目橙线，默认隐藏，由「路网」开关控制）。
            // 高亮整个 transportation 路网（道路 + 徒步小径）——城区/野外都能看到，不再只筛 path 类。
            ["id": "road-network", "type": "line", "source": "v", "source-layer": "transportation",
             "layout": ["visibility": "none", "line-cap": "round", "line-join": "round"],
             "paint": ["line-color": "#F36B22", "line-width": netWidth, "line-opacity": 0.9]],
            fill("building", "building", "#D9CFC2", 0.7),
            ["id": "boundary", "type": "line", "source": "v", "source-layer": "boundary",
             "paint": ["line-color": "#9A8FB0", "line-width": 0.8, "line-dasharray": [3.0, 2.0]]]
        ]

        // ===== 文字标注层（叠在最上层）=====
        let nameField: [Any] = ["coalesce", ["get", "name:zh"], ["get", "name:latin"], ["get", "name"]]

        // 道路名（沿线排布）
        ls.append([
            "id": "road-name", "type": "symbol", "source": "v", "source-layer": "transportation_name",
            "minzoom": 13,
            "layout": [
                "symbol-placement": "line",
                "text-field": nameField,
                "text-font": fontStack,
                "text-size": ["interpolate", ["linear"], ["zoom"], 13, 10.0, 17, 13.0]
            ],
            "paint": ["text-color": "#5A4632", "text-halo-color": "#FFFFFF", "text-halo-width": 1.2]
        ])

        // 水名
        ls.append([
            "id": "water-name", "type": "symbol", "source": "v", "source-layer": "water_name",
            "layout": [
                "text-field": nameField,
                "text-font": fontStack,
                "text-size": ["interpolate", ["linear"], ["zoom"], 10, 10.0, 16, 14.0]
            ],
            "paint": ["text-color": "#2E6E9E", "text-halo-color": "#FFFFFF", "text-halo-width": 1.2]
        ])

        // 山峰名（名称 + 换行 + 海拔米数；用 concat 而非 format，兼容性更好）
        let peakField: [Any] = ["concat", nameField, "\n",
                                ["to-string", ["coalesce", ["get", "ele"], ""]], " m"]
        ls.append([
            "id": "peak-label", "type": "symbol", "source": "v", "source-layer": "mountain_peak",
            "minzoom": 11,
            "layout": [
                "text-field": peakField,
                "text-font": fontStack,
                "text-size": 12.0,
                "text-anchor": "top",
                "text-offset": [0.0, 0.4]
            ],
            "paint": ["text-color": "#6A4A2A", "text-halo-color": "#FFFFFF", "text-halo-width": 1.4]
        ])

        // 地名（按 rank 分级字号；居民点/行政地名）
        ls.append([
            "id": "place-label", "type": "symbol", "source": "v", "source-layer": "place",
            "layout": [
                "text-field": nameField,
                "text-font": fontStack,
                "text-size": ["interpolate", ["linear"], ["zoom"],
                              4, ["interpolate", ["linear"], ["get", "rank"], 1, 16.0, 10, 11.0],
                              12, ["interpolate", ["linear"], ["get", "rank"], 1, 24.0, 10, 14.0]],
                "text-max-width": 8.0
            ],
            "paint": ["text-color": "#33302B", "text-halo-color": "#FFFFFF", "text-halo-width": 1.6]
        ])

        return ls
    }
}
