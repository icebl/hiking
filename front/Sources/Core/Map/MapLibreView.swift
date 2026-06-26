import SwiftUI
import UIKit
import MapLibre
import CoreLocation

/// MapLibre 地图封装（任务 2.1~2.4）。WGS-84。
/// 当前底图：**在线栅格**（开发期联调，默认 OSM）；离线 PMTiles 矢量底图后续替换（任务 2.2）。
struct MapLibreView: UIViewRepresentable {

    /// 控制桥接：缩放/定位/居中由 SwiftUI 控件经 MapController 调用（任务 2.3）。
    var controller: MapController? = nil

    /// 底图模式：在线栅格(ESRI) / 离线矢量(本地 PMTiles)（任务 2.2 / 2.6）
    var baseMode: MapBaseMode = .onlineRaster

    var trackCoordinates: [CLLocationCoordinate2D] = []
    var showsUserLocation: Bool = true
    /// true 时：有轨迹则自动把相机框到轨迹范围（轨迹详情用）
    var fitToTrack: Bool = false
    /// true 时：轨迹上每 1km 显示里程碑（公里标）
    var showKmMarkers: Bool = false
    /// 等高线（任务 2.5）：开关 + 等高线包本地路径（叠在任何底图之上）
    var showContours: Bool = false
    var contourPath: String? = nil
    /// 点击地图回调（取经纬度，任务 2.8）
    var onTap: ((CLLocationCoordinate2D) -> Void)? = nil

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
        context.coordinator.lastBaseMode = baseMode
        map.styleURL = Self.styleURL(for: baseMode)
        map.showsUserLocation = showsUserLocation
        map.showsUserHeadingIndicator = true      // 蓝点朝向箭头，随手机方向旋转
        map.logoView.isHidden = true
        map.attributionButton.isHidden = true         // 隐藏版权(i)按钮（遮挡操作；发布前在“关于”补署名）
        map.setCenter(initialCenter, zoomLevel: initialZoom, animated: false)
        if onTap != nil {
            let tap = UITapGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handleTap(_:)))
            map.addGestureRecognizer(tap)
        }
        controller?.mapView = map
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        let coord = context.coordinator
        coord.parent = self
        coord.coords = trackCoordinates
        if coord.lastBaseMode != baseMode {          // 底图切换 → 换 style（didFinishLoading 重建图层）
            coord.lastBaseMode = baseMode
            map.styleURL = Self.styleURL(for: baseMode)
        }
        coord.drawTrack(on: map)
        coord.updateKmMarkers(on: map, show: showKmMarkers)
        coord.updateContours(on: map)
    }

    /// 按底图模式返回 styleURL：在线=空 style(随后加栅格)，离线=矢量 PMTiles 样式。
    static func styleURL(for mode: MapBaseMode) -> URL {
        switch mode {
        case .onlineRaster:          return blankStyleURL()
        case .offlineVector(let p):  return OfflineVectorStyle.styleURL(pmtilesPath: p)
        case .offlineRaster(let p):  return OfflineRasterStyle.styleURL(mbtilesPath: p)
        }
    }

    /// 最小空 style（version 8），在线栅格源/层在 didFinishLoading 里程序化加入。
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
        var lastBaseMode: MapBaseMode = .onlineRaster
        private var trackSource: MLNShapeSource?
        private var didFit = false
        private var endpointsAdded = false      // 起终点为标注(跨样式重载存活)，只加一次

        init(_ parent: MapLibreView) {
            self.parent = parent
            self.coords = parent.trackCoordinates
        }

        /// style (重)载完成：旧源已随样式失效，复位后重建底图(在线栅格)与轨迹叠加。
        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            trackSource = nil          // 样式重载后旧的 track 源/箭头层已不在，置空以重建
            arrowZoomBucket = -100
            if case .onlineRaster = parent.baseMode,
               style.source(withIdentifier: "raster-base") == nil {
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
            // 离线矢量底图：样式 JSON 已含矢量源/层，无需在此添加
            drawTrack(on: mapView)
            updateContours(on: mapView)     // 等高线叠加（样式重载后重建）
            parent.controller?.zoom = mapView.zoomLevel
        }

        // 自定义标注：用户位置朝向箭头 / 起终点（圆 + 起·终 文字）
        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            if annotation is MLNUserLocation { return HeadingUserLocationView() }
            if let e = annotation as? EndpointAnnotation { return EndpointMarkerView(isStart: e.isStart) }
            if let k = annotation as? KmAnnotation { return KmMarkerView(km: k.km) }
            return nil
        }

        // 跟随模式变化（用户拖动会打断 .follow）→ 同步定位键高亮
        func mapView(_ mapView: MLNMapView, didChange mode: MLNUserTrackingMode, animated: Bool) {
            parent.controller?.syncTrackingMode(mode)
        }

        // 点击地图取经纬度（任务 2.8）
        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let map = g.view as? MLNMapView else { return }
            let coord = map.convert(g.location(in: map), toCoordinateFrom: map)
            parent.onTap?(coord)
        }

        // 缩放级别读数回填（任务诊断用）
        func mapViewRegionIsChanging(_ mapView: MLNMapView) {
            parent.controller?.zoom = mapView.zoomLevel
        }
        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            parent.controller?.zoom = mapView.zoomLevel
            rebuildArrows(on: mapView)      // 缩放变化时按比例尺调整箭头密度
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
                    rebuildArrows(on: map)
                    if !endpointsAdded { addEndpoints(on: map); endpointsAdded = true }  // 标注跨重载存活，只加一次
                }
            }
            fitIfNeeded(on: map)
        }

        private var arrowZoomBucket = -100

        /// 方向箭头：方向用线段方位角(同向)，**密度随缩放变化**——约每 80 屏幕像素一个，
        /// 放大→间隔变小→箭头变多。按整数缩放分桶，仅变化时重建。
        private func rebuildArrows(on map: MLNMapView) {
            guard parent.fitToTrack, coords.count > 1, let style = map.style else { return }
            let zoom = map.zoomLevel
            let bucket = Int(zoom.rounded())
            if bucket == arrowZoomBucket { return }
            arrowZoomBucket = bucket

            if let l = style.layer(withIdentifier: "track-arrows") { style.removeLayer(l) }
            if let s = style.source(withIdentifier: "track-arrows-src") { style.removeSource(s) }
            if style.image(forName: "trk-chevron") == nil {
                style.setImage(Self.chevronImage(), forName: "trk-chevron")
            }

            // 每像素米数 → 目标约每 80px 一个箭头（最小 40m，避免极近时过密）
            let lat = coords[coords.count / 2].latitude
            let mpp = 156543.03392 * cos(lat * .pi / 180) / pow(2.0, zoom)
            let interval = max(40.0, mpp * 80)

            var feats: [MLNPointFeature] = []
            var acc = 0.0, nextAt = interval
            for i in 1..<coords.count {
                let a = CLLocation(latitude: coords[i-1].latitude, longitude: coords[i-1].longitude)
                let b = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
                let seg = b.distance(from: a)
                guard seg > 0 else { continue }
                let brng = Self.bearing(from: coords[i-1], to: coords[i])
                while acc + seg >= nextAt {
                    let t = (nextAt - acc) / seg
                    let plat = coords[i-1].latitude + (coords[i].latitude - coords[i-1].latitude) * t
                    let plon = coords[i-1].longitude + (coords[i].longitude - coords[i-1].longitude) * t
                    let f = MLNPointFeature()
                    f.coordinate = CLLocationCoordinate2D(latitude: plat, longitude: plon)
                    f.attributes = ["b": brng]
                    feats.append(f)
                    nextAt += interval
                }
                acc += seg
            }
            guard !feats.isEmpty else { return }
            let src = MLNShapeSource(identifier: "track-arrows-src", features: feats, options: nil)
            style.addSource(src)
            let layer = MLNSymbolStyleLayer(identifier: "track-arrows", source: src)
            layer.iconImageName = NSExpression(forConstantValue: "trk-chevron")
            layer.iconRotation = NSExpression(forKeyPath: "b")        // 按方位角旋转（朝上图标旋到行进方向）
            layer.iconRotationAlignment = NSExpression(forConstantValue: "map")
            layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            style.addLayer(layer)
        }

        /// 起点/终点标注（圆 + “起”“终”文字），用自定义标注视图（不依赖字体 glyphs）。
        private func addEndpoints(on map: MLNMapView) {
            guard let first = coords.first, let last = coords.last else { return }
            let start = EndpointAnnotation(); start.coordinate = first; start.isStart = true
            let end = EndpointAnnotation(); end.coordinate = last; end.isStart = false
            map.addAnnotations([start, end])
        }

        /// A→B 方位角（度，顺时针自正北）。
        private static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
            let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
            let dLon = (b.longitude - a.longitude) * .pi / 180
            let y = sin(dLon) * cos(lat2)
            let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
            let deg = atan2(y, x) * 180 / .pi
            return (deg + 360).truncatingRemainder(dividingBy: 360)
        }

        private var kmAnnotations: [MLNAnnotation] = []

        /// 公里标：每 1km 一个里程碑（深色圆+白数字）。用标注视图（不依赖字体 glyphs）。开关。
        func updateKmMarkers(on map: MLNMapView, show: Bool) {
            if show {
                guard kmAnnotations.isEmpty, coords.count > 1 else { return }   // 已显示则不重复添加
                var anns: [MLNAnnotation] = []
                var acc = 0.0, nextKm = 1.0
                for i in 1..<coords.count {
                    let a = CLLocation(latitude: coords[i-1].latitude, longitude: coords[i-1].longitude)
                    let b = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
                    let seg = b.distance(from: a)
                    guard seg > 0 else { continue }
                    while acc + seg >= nextKm * 1000 {
                        let t = (nextKm * 1000 - acc) / seg
                        let lat = coords[i-1].latitude + (coords[i].latitude - coords[i-1].latitude) * t
                        let lon = coords[i-1].longitude + (coords[i].longitude - coords[i-1].longitude) * t
                        let m = KmAnnotation()
                        m.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                        m.km = Int(nextKm)
                        anns.append(m)
                        nextKm += 1
                    }
                    acc += seg
                }
                guard !anns.isEmpty else { return }
                map.addAnnotations(anns)
                kmAnnotations = anns
            } else {
                guard !kmAnnotations.isEmpty else { return }
                map.removeAnnotations(kmAnnotations)
                kmAnnotations = []
            }
        }

        /// 等高线叠加层（任务 2.5）：青色细线 + 计曲线(idx==1)加粗；叠在底图之上、轨迹之下。
        func updateContours(on map: MLNMapView) {
            guard let style = map.style else { return }
            let srcId = "contour-src", lineId = "contour-line", idxId = "contour-index"
            for id in [idxId, lineId] { if let l = style.layer(withIdentifier: id) { style.removeLayer(l) } }
            if let s = style.source(withIdentifier: srcId) { style.removeSource(s) }
            guard parent.showContours, let path = parent.contourPath,
                  let url = URL(string: "pmtiles://\(URL(fileURLWithPath: path).absoluteString)") else { return }

            let src = MLNVectorTileSource(identifier: srcId, configurationURL: url)
            style.addSource(src)

            let line = MLNLineStyleLayer(identifier: lineId, source: src)
            line.sourceLayerIdentifier = "contour"
            line.lineColor = NSExpression(forConstantValue: UIColor(red: 0.21, green: 0.77, blue: 0.75, alpha: 1)) // #36C5C0
            line.lineWidth = NSExpression(forConstantValue: 0.9)
            line.lineOpacity = NSExpression(forConstantValue: 0.7)
            line.minimumZoomLevel = 12

            let idx = MLNLineStyleLayer(identifier: idxId, source: src)
            idx.sourceLayerIdentifier = "contour"
            idx.predicate = NSPredicate(format: "idx == 1")
            idx.lineColor = NSExpression(forConstantValue: UIColor(red: 0.18, green: 0.66, blue: 0.64, alpha: 1)) // #2FA8A3
            idx.lineWidth = NSExpression(forConstantValue: 1.7)
            idx.lineOpacity = NSExpression(forConstantValue: 0.85)
            idx.minimumZoomLevel = 11

            if let track = style.layer(withIdentifier: "track-line") {   // 等高线在红轨迹之下
                style.insertLayer(line, below: track)
                style.insertLayer(idx, below: track)
            } else {
                style.addLayer(line); style.addLayer(idx)
            }
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

        /// 空心 V 形 chevron（朝上），随 iconRotation 旋到行进方向；白线+浅黑描边便于亮底可见。
        private static func chevronImage() -> UIImage {
            let size = CGSize(width: 20, height: 20)
            return UIGraphicsImageRenderer(size: size).image { ctx in
                let c = ctx.cgContext
                let p = UIBezierPath()
                p.move(to: CGPoint(x: 4, y: 13))     // 左臂
                p.addLine(to: CGPoint(x: 10, y: 6))  // 顶点（朝上）
                p.addLine(to: CGPoint(x: 16, y: 13)) // 右臂
                c.setLineCap(.round); c.setLineJoin(.round)
                // 先描一层深色加宽做轮廓，再描白色
                c.setStrokeColor(UIColor(white: 0, alpha: 0.55).cgColor); c.setLineWidth(5)
                c.addPath(p.cgPath); c.strokePath()
                c.setStrokeColor(UIColor.white.cgColor); c.setLineWidth(2.6)
                c.addPath(p.cgPath); c.strokePath()
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

/// 起终点标注数据：isStart 区分起(绿“起”)/终(红“终”)。
final class EndpointAnnotation: MLNPointAnnotation {
    var isStart = true
}

/// 公里标标注数据：km = 第几公里。
final class KmAnnotation: MLNPointAnnotation {
    var km = 0
}

/// 公里标视图：深色圆 + 白色公里数（参照图26）。
final class KmMarkerView: MLNAnnotationView {
    init(km: Int) {
        super.init(reuseIdentifier: "km-\(km)")
        frame = CGRect(x: 0, y: 0, width: 22, height: 22)
        layer.backgroundColor = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 0.92).cgColor
        layer.cornerRadius = 11
        layer.borderColor = UIColor.white.cgColor
        layer.borderWidth = 1.5
        let label = UILabel(frame: bounds)
        label.text = "\(km)"
        label.textColor = .white
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textAlignment = .center
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// 起终点标注视图：圆形底 + 白色“起/终”文字。
final class EndpointMarkerView: MLNAnnotationView {
    init(isStart: Bool) {
        super.init(reuseIdentifier: isStart ? "ep-start" : "ep-end")
        frame = CGRect(x: 0, y: 0, width: 28, height: 28)
        let color = isStart ? UIColor(red: 0.12, green: 0.62, blue: 0.33, alpha: 1)   // 绿
                            : UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1)     // 红
        layer.backgroundColor = color.cgColor
        layer.cornerRadius = 14
        layer.borderColor = UIColor.white.cgColor
        layer.borderWidth = 2
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25; layer.shadowRadius = 2; layer.shadowOffset = .zero
        let label = UILabel(frame: bounds)
        label.text = isStart ? "起" : "终"
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .bold)
        label.textAlignment = .center
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
