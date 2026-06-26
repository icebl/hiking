import Foundation
import UIKit
import CoreLocation
import MapLibre

/// 地图控制桥接（任务 2.3）：SwiftUI 悬浮控件 ↔ MLNMapView。
/// MapLibreView 在 makeUIView 时把 map 注入这里，控件回调再调用本类方法。
final class MapController: ObservableObject {
    weak var mapView: MLNMapView?

    /// 当前地图缩放级别（诊断/读数用，由 MapLibreView 在地图变动时回填）。
    @Published var zoom: Double = 0

    /// 定位键状态（单击循环：居中一次 → 跟随 → 关闭）。
    enum LocateState { case off, centered, following }
    @Published var locateState: LocateState = .off

    var minZoom: Double = 1
    var maxZoom: Double = 18

    /// 当前轨迹坐标（由 MapLibreView 回填），用于「回到原点」重新框住。
    var fitCoords: [CLLocationCoordinate2D] = []

    /// 把相机框到给定经纬度范围（如离线影像包覆盖区）。
    func fit(sw: CLLocationCoordinate2D, ne: CLLocationCoordinate2D, animated: Bool = true) {
        guard let m = mapView, m.bounds.width > 10, m.bounds.height > 10 else { return }
        let bounds = MLNCoordinateBounds(sw: sw, ne: ne)
        m.setVisibleCoordinateBounds(bounds,
            edgePadding: UIEdgeInsets(top: 60, left: 40, bottom: 60, right: 40), animated: animated)
    }

    /// 把相机框到轨迹范围（含边距）。
    func fitTrack(animated: Bool = true) {
        guard let m = mapView, fitCoords.count > 1 else { return }
        guard m.bounds.width > 10, m.bounds.height > 10 else { return }  // 防零尺寸算出 NaN 相机崩溃
        var minLat = fitCoords[0].latitude, maxLat = fitCoords[0].latitude
        var minLon = fitCoords[0].longitude, maxLon = fitCoords[0].longitude
        for c in fitCoords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let bounds = MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
            ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon))
        m.setVisibleCoordinateBounds(bounds,
            edgePadding: UIEdgeInsets(top: 60, left: 40, bottom: 60, right: 40), animated: animated)
    }

    /// 放大一级
    func zoomIn() {
        guard let m = mapView else { return }
        m.setZoomLevel(m.zoomLevel + 1, animated: true)
    }

    /// 缩小一级
    func zoomOut() {
        guard let m = mapView else { return }
        m.setZoomLevel(m.zoomLevel - 1, animated: true)
    }

    /// 滑块：0…1 映射到 [minZoom, maxZoom]
    func setZoom(fraction f: Double) {
        guard let m = mapView else { return }
        let clamped = max(0, min(1, f))
        m.setZoomLevel(minZoom + (maxZoom - minZoom) * clamped, animated: false)
    }

    /// 定位键单击：off → 居中一次；centered → 进入跟随；following → 关闭。
    func cycleLocate() {
        guard let m = mapView else { return }
        switch locateState {
        case .off:
            if let loc = m.userLocation?.location {
                m.setCenter(loc.coordinate, zoomLevel: max(m.zoomLevel, 14), animated: true)
            }
            locateState = .centered
        case .centered:
            m.userTrackingMode = .follow      // 进入跟随
            locateState = .following
        case .following:
            m.userTrackingMode = .none
            locateState = .off
        }
    }

    /// 同步系统跟随模式变化（用户拖动地图会打断跟随 → 复位按钮高亮）。
    func syncTrackingMode(_ mode: MLNUserTrackingMode) {
        if mode == .none && locateState == .following { locateState = .off }
    }
}
