import SwiftUI
import MapLibre

/// MapLibre 地图封装（任务 2.1~2.4）。WGS-84；矢量底图 + 等高线 + 轨迹叠加。
struct MapLibreView: UIViewRepresentable {

    var styleURL: URL? = nil            // 自带矢量 style（PMTiles），任务 2.2
    var trackCoordinates: [CLLocationCoordinate2D] = []
    var showsUserLocation: Bool = true
    var showContours: Bool = true       // 等高线开关（任务 2.5）

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero)
        map.delegate = context.coordinator
        if let styleURL { map.styleURL = styleURL }
        map.showsUserLocation = showsUserLocation
        map.logoView.isHidden = true
        map.attributionButton.isHidden = false   // 保留版权署名（OSM）
        // TODO(2.3): 自定义缩放/居中/公里标控件由 SwiftUI 层叠加
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.drawTrack(on: map, coords: trackCoordinates)
        // TODO(2.5): 根据 showContours 切换等高线图层可见性
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        private var trackSource: MLNShapeSource?

        func drawTrack(on map: MLNMapView, coords: [CLLocationCoordinate2D]) {
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
