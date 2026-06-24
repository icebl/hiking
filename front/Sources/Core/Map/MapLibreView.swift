import SwiftUI
import MapLibre
import CoreLocation

/// MapLibre 地图封装（任务 2.1~2.4）。WGS-84。
/// 当前底图：**在线栅格**（开发期联调，默认 OSM）；离线 PMTiles 矢量底图后续替换（任务 2.2）。
struct MapLibreView: UIViewRepresentable {

    /// 控制桥接：缩放/定位/居中由 SwiftUI 控件经 MapController 调用（任务 2.3）。
    var controller: MapController? = nil

    var trackCoordinates: [CLLocationCoordinate2D] = []
    var showsUserLocation: Bool = true

    /// 在线栅格底图模板（单常量便于切换到 T_Google 等）。上线/离线仍走自建底图。
    var rasterTileURLTemplate: String = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
    var initialCenter = CLLocationCoordinate2D(latitude: 41.80, longitude: 123.43)  // 默认沈阳
    var initialZoom: Double = 11

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero)
        map.delegate = context.coordinator
        map.styleURL = Self.blankStyleURL()
        map.showsUserLocation = showsUserLocation
        map.logoView.isHidden = true
        map.attributionButton.isHidden = false       // 保留版权署名（OSM）
        map.setCenter(initialCenter, zoomLevel: initialZoom, animated: false)
        controller?.mapView = map
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.coords = trackCoordinates
        context.coordinator.drawTrack(on: map)
    }

    /// 最小空 style（version 8），底图源/层在 didFinishLoading 里程序化加入。
    private static func blankStyleURL() -> URL {
        let json = #"{"version":8,"sources":{},"layers":[]}"#
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("blank-style.json")
        try? json.data(using: .utf8)?.write(to: url)
        return url
    }

    // MARK: - Coordinator
    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: MapLibreView
        var coords: [CLLocationCoordinate2D]
        private var trackSource: MLNShapeSource?

        init(_ parent: MapLibreView) {
            self.parent = parent
            self.coords = parent.trackCoordinates
        }

        /// style 加载完成：加入在线栅格底图（任务 2.2 临时方案），再叠加轨迹。
        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            if style.source(withIdentifier: "raster-base") == nil {
                let src = MLNRasterTileSource(
                    identifier: "raster-base",
                    tileURLTemplates: [parent.rasterTileURLTemplate],
                    options: [
                        .tileSize: 256,
                        .minimumZoomLevel: 0,
                        .maximumZoomLevel: 19
                    ])
                style.addSource(src)
                let layer = MLNRasterStyleLayer(identifier: "raster-base-layer", source: src)
                style.addLayer(layer)
            }
            drawTrack(on: mapView)
        }

        /// 绘制/更新轨迹折线（任务 2.4），叠加在底图之上。
        func drawTrack(on map: MLNMapView) {
            guard coords.count > 1, let style = map.style else { return }
            var pts = coords
            let polyline = MLNPolylineFeature(coordinates: &pts, count: UInt(pts.count))
            if let src = trackSource {
                src.shape = polyline
            } else {
                let src = MLNShapeSource(identifier: "track", shape: polyline, options: nil)
                style.addSource(src)
                let layer = MLNLineStyleLayer(identifier: "track-line", source: src)
                layer.lineColor = NSExpression(forConstantValue: UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1)) // #FF3B30
                layer.lineWidth = NSExpression(forConstantValue: 4)
                layer.lineCap = NSExpression(forConstantValue: "round")
                style.addLayer(layer)
                trackSource = src
            }
        }
    }
}
