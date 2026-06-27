import Foundation

/// 在线 ESRI 卫星栅格 style（任务 2.7 / S2-B 改用官方离线）。
/// 作为 MLNTilePyramidOfflineRegion 的 styleURL：MapLibre 据此把该区域的 ESRI 瓦片下载并钉入自带离线缓存。
/// 瓦片 URL 与地图在线底图(MapLibreView.rasterTileURLTemplate)一致 → 离线时按 URL 命中缓存渲染。
enum OnlineRasterStyle {
    static let esriImageryTemplate =
        "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"

    /// 写到稳定路径（Application Support），返回 styleURL。
    static func styleURL() -> URL {
        let style: [String: Any] = [
            "version": 8,
            "name": "esri-imagery",
            // maxzoom 19：ESRI World Imagery 提供的最高瓦片级别
            "sources": ["esri": ["type": "raster", "tiles": [esriImageryTemplate],
                                  "tileSize": 256, "minzoom": 0, "maxzoom": 19]],
            "layers": [["id": "esri", "type": "raster", "source": "esri"]]
        ]
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("esri-imagery-style.json")
        if let data = try? JSONSerialization.data(withJSONObject: style) {
            try? data.write(to: url)
        }
        return url
    }
}
