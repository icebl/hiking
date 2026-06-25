import SwiftUI
import UIKit
import MapLibre
import CoreLocation

/// MapLibre 地图封装（任务 2.1~2.4）。WGS-84。
/// 当前底图：**在线栅格**（开发期联调，默认 OSM）；离线 PMTiles 矢量底图后续替换（任务 2.2）。
struct MapLibreView: UIViewRepresentable {

    /// 控制桥接：缩放/定位/居中由 SwiftUI 控件经 MapController 调用（任务 2.3）。
    var controller: MapController? = nil

    var trackCoordinates: [CLLocationCoordinate2D] = []
    var showsUserLocation: Bool = true

    /// 在线栅格底图模板（单常量便于切换）。上线/离线仍走自建底图。
    /// 说明：OSM 公共瓦片对 UA 有策略限制→白图；ESRI 世界地形图(World_Topo_Map)在中国区高层级(~z16+)无缓存，
    /// 会返回 "Map data not yet available" 灰瓦片。故默认用 **ESRI 世界影像(卫星)**：中国区可靠覆盖到 ~z18，层级足够深。
    /// 备选地形图：https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}
    var rasterTileURLTemplate: String = "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
    /// 栅格源最高级别：超过则过缩放(overzoom)复用该级瓦片，避免请求到无数据的灰瓦片。
    var rasterMaxZoom: Int = 18
    var initialCenter = CLLocationCoordinate2D(latitude: 41.80, longitude: 123.43)  // 默认沈阳
    var initialZoom: Double = 11

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero)
        map.delegate = context.coordinator
        map.styleURL = Self.blankStyleURL()
        map.showsUserLocation = showsUserLocation
        map.showsUserHeadingIndicator = true      // 蓝点朝向箭头，随手机方向旋转
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
                        .maximumZoomLevel: parent.rasterMaxZoom
                    ])
                style.addSource(src)
                let layer = MLNRasterStyleLayer(identifier: "raster-base-layer", source: src)
                style.addLayer(layer)
            }
            drawTrack(on: mapView)
            parent.controller?.zoom = mapView.zoomLevel
        }

        // 自定义用户位置标注：更大更长的朝向箭头（随手机方向旋转）
        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            guard annotation is MLNUserLocation else { return nil }
            return HeadingUserLocationView()
        }

        // 缩放级别读数回填（任务诊断用）
        func mapViewRegionIsChanging(_ mapView: MLNMapView) {
            parent.controller?.zoom = mapView.zoomLevel
        }
        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            parent.controller?.zoom = mapView.zoomLevel
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

/// 自定义用户位置视图：白边蓝点 + 更大更长的朝向箭头（heading 旋转）。
final class HeadingUserLocationView: MLNUserLocationAnnotationView {
    private let arrow = CAShapeLayer()
    private let dot = CALayer()
    private var built = false

    private static let blue = UIColor(red: 0.12, green: 0.49, blue: 1.0, alpha: 1)

    override func update() {
        if frame.isNull {                 // 首次：给定尺寸后等下一帧布局
            frame = CGRect(x: 0, y: 0, width: 64, height: 64)
            return setNeedsLayout()
        }
        if !built { build(); built = true }
        // 朝向旋转（trueHeading 优先；无则不转）
        if let heading = userLocation?.heading?.trueHeading, heading >= 0 {
            arrow.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(heading * .pi / 180)))
        }
    }

    private func build() {
        let c = CGPoint(x: bounds.midX, y: bounds.midY)

        // 箭头：以中心为旋转锚点，尖端在中心上方（更长 = 距中心更远）
        let w: CGFloat = 22, len: CGFloat = 30, baseGap: CGFloat = 6
        let path = UIBezierPath()
        path.move(to: CGPoint(x: c.x, y: c.y - len))            // 尖端
        path.addLine(to: CGPoint(x: c.x - w / 2, y: c.y - baseGap))
        path.addLine(to: CGPoint(x: c.x, y: c.y - baseGap * 2.2))
        path.addLine(to: CGPoint(x: c.x + w / 2, y: c.y - baseGap))
        path.close()
        arrow.path = path.cgPath
        arrow.fillColor = Self.blue.cgColor
        arrow.frame = bounds
        arrow.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        arrow.position = c
        arrow.shadowColor = UIColor.black.cgColor
        arrow.shadowOpacity = 0.25; arrow.shadowRadius = 2; arrow.shadowOffset = .zero
        layer.addSublayer(arrow)

        // 中心圆点（白边）
        let r: CGFloat = 9
        dot.frame = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        dot.cornerRadius = r
        dot.backgroundColor = Self.blue.cgColor
        dot.borderColor = UIColor.white.cgColor
        dot.borderWidth = 3
        layer.addSublayer(dot)
    }
}
