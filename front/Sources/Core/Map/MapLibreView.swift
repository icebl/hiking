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
    /// true 时：有轨迹则自动把相机框到轨迹范围（轨迹详情用）
    var fitToTrack: Bool = false
    /// true 时：轨迹上每 1km 显示里程碑（公里标）
    var showKmMarkers: Bool = false

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
        map.attributionButton.isHidden = true         // 隐藏版权(i)按钮（遮挡操作；发布前在“关于”补署名）
        map.setCenter(initialCenter, zoomLevel: initialZoom, animated: false)
        controller?.mapView = map
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.coords = trackCoordinates
        context.coordinator.drawTrack(on: map)
        context.coordinator.updateKmMarkers(on: map, show: showKmMarkers)
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
        private var didFit = false

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

        // 跟随模式变化（用户拖动会打断 .follow）→ 同步定位键高亮
        func mapView(_ mapView: MLNMapView, didChange mode: MLNUserTrackingMode, animated: Bool) {
            parent.controller?.syncTrackingMode(mode)
        }

        // 缩放级别读数回填（任务诊断用）
        func mapViewRegionIsChanging(_ mapView: MLNMapView) {
            parent.controller?.zoom = mapView.zoomLevel
        }
        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            parent.controller?.zoom = mapView.zoomLevel
        }

        /// 绘制/更新轨迹折线 + 起终点圈 + 方向箭头（任务 2.4 / 图7）。
        func drawTrack(on map: MLNMapView) {
            guard coords.count > 1, let style = map.style else { return }
            parent.controller?.fitCoords = coords
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
                if parent.fitToTrack {           // 仅完整/计划轨迹（详情、导航）画起终点+箭头；记录中的实时线不画
                    addDirectionArrows(on: style, lineSource: src)
                    addEndpoints(on: style)
                }
            }
            fitIfNeeded(on: map)
        }

        /// 沿线方向箭头：注册白色箭头图，符号层沿线方向重复排布。
        private func addDirectionArrows(on style: MLNStyle, lineSource: MLNShapeSource) {
            if style.image(forName: "trk-arrow") == nil {
                style.setImage(Self.arrowImage(), forName: "trk-arrow")
            }
            let layer = MLNSymbolStyleLayer(identifier: "track-arrows", source: lineSource)
            layer.iconImageName = NSExpression(forConstantValue: "trk-arrow")
            layer.symbolPlacement = NSExpression(forConstantValue: "line")
            layer.symbolSpacing = NSExpression(forConstantValue: 90)
            layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            layer.iconRotationAlignment = NSExpression(forConstantValue: "map")
            style.addLayer(layer)
        }

        /// 起点绿圈 / 终点红圈（两个常量色圆层，避免表达式风险）。
        private func addEndpoints(on style: MLNStyle) {
            guard let first = coords.first, let last = coords.last else { return }
            addEndCircle(on: style, id: "track-start", coord: first,
                         color: UIColor(red: 0.12, green: 0.62, blue: 0.33, alpha: 1))  // #1F9D55 绿
            addEndCircle(on: style, id: "track-end", coord: last,
                         color: UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1))    // #FF3B30 红
        }
        private func addEndCircle(on style: MLNStyle, id: String, coord: CLLocationCoordinate2D, color: UIColor) {
            let f = MLNPointFeature(); f.coordinate = coord
            let src = MLNShapeSource(identifier: id, shape: f, options: nil)
            style.addSource(src)
            let layer = MLNCircleStyleLayer(identifier: id + "-layer", source: src)
            layer.circleColor = NSExpression(forConstantValue: color)
            layer.circleRadius = NSExpression(forConstantValue: 8)
            layer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            layer.circleStrokeWidth = NSExpression(forConstantValue: 2)
            style.addLayer(layer)
        }

        /// 公里标：每 1km 一个里程碑（开关）。
        func updateKmMarkers(on map: MLNMapView, show: Bool) {
            guard let style = map.style else { return }
            let srcId = "km-markers", layerId = "km-markers-layer"
            if let l = style.layer(withIdentifier: layerId) { style.removeLayer(l) }
            if let s = style.source(withIdentifier: srcId) { style.removeSource(s) }
            guard show, coords.count > 1 else { return }

            var feats: [MLNPointFeature] = []
            var acc = 0.0
            var nextKm = 1.0
            for i in 1..<coords.count {
                let a = CLLocation(latitude: coords[i-1].latitude, longitude: coords[i-1].longitude)
                let b = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
                let seg = b.distance(from: a)
                while acc + seg >= nextKm * 1000 {
                    let t = (nextKm * 1000 - acc) / seg
                    let lat = coords[i-1].latitude + (coords[i].latitude - coords[i-1].latitude) * t
                    let lon = coords[i-1].longitude + (coords[i].longitude - coords[i-1].longitude) * t
                    let f = MLNPointFeature()
                    f.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    f.attributes = ["label": String(format: "%.0f", nextKm)]
                    feats.append(f)
                    nextKm += 1
                }
                acc += seg
            }
            guard !feats.isEmpty else { return }
            let src = MLNShapeSource(identifier: srcId, features: feats, options: nil)
            style.addSource(src)
            let layer = MLNSymbolStyleLayer(identifier: layerId, source: src)
            layer.text = NSExpression(forKeyPath: "label")
            layer.textColor = NSExpression(forConstantValue: UIColor.white)
            layer.textHaloColor = NSExpression(forConstantValue: UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1))
            layer.textHaloWidth = NSExpression(forConstantValue: 2)
            layer.textFontSize = NSExpression(forConstantValue: 12)
            layer.textAllowsOverlap = NSExpression(forConstantValue: true)
            style.addLayer(layer)
        }

        /// 有轨迹时把相机框到轨迹范围（仅一次，详情/导航用）。不依赖 controller。
        private func fitIfNeeded(on map: MLNMapView) {
            guard parent.fitToTrack, !didFit, coords.count > 1 else { return }
            // 地图尺寸为 0 时调用 setVisibleCoordinateBounds 会算出 NaN 相机而崩溃；不满足则不置 didFit，稍后重试
            guard map.bounds.width > 10, map.bounds.height > 10 else { return }
            var minLat = coords[0].latitude, maxLat = coords[0].latitude
            var minLon = coords[0].longitude, maxLon = coords[0].longitude
            for c in coords {
                minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
                minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
            }
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
                ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon))
            map.setVisibleCoordinateBounds(bounds,
                edgePadding: UIEdgeInsets(top: 60, left: 40, bottom: 60, right: 40), animated: false)
            didFit = true
        }

        /// 生成沿线方向箭头图（白色实心三角，深描边以便在亮底可见）。
        private static func arrowImage() -> UIImage {
            let size = CGSize(width: 18, height: 18)
            return UIGraphicsImageRenderer(size: size).image { ctx in
                let c = ctx.cgContext
                let p = UIBezierPath()
                p.move(to: CGPoint(x: 9, y: 3))      // 尖端朝上：沿线符号按方位角旋转后即指向前进方向
                p.addLine(to: CGPoint(x: 4, y: 14))
                p.addLine(to: CGPoint(x: 14, y: 14))
                p.close()
                c.setFillColor(UIColor.white.cgColor)
                c.setStrokeColor(UIColor(white: 0, alpha: 0.5).cgColor)
                c.setLineWidth(1)
                c.addPath(p.cgPath); c.drawPath(using: .fillStroke)
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
