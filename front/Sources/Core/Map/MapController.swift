import Foundation
import MapLibre

/// 地图控制桥接（任务 2.3）：SwiftUI 悬浮控件 ↔ MLNMapView。
/// MapLibreView 在 makeUIView 时把 map 注入这里，控件回调再调用本类方法。
final class MapController: ObservableObject {
    weak var mapView: MLNMapView?

    var minZoom: Double = 1
    var maxZoom: Double = 18

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

    /// 定位：移到当前位置并进入跟随模式
    func recenterOnUser() {
        guard let m = mapView else { return }
        if let loc = m.userLocation?.location {
            m.setCenter(loc.coordinate, zoomLevel: max(m.zoomLevel, 14), animated: true)
        }
        m.userTrackingMode = .follow
    }

    /// 居中：回到当前位置但不进入跟随模式
    func center() {
        guard let m = mapView else { return }
        guard let loc = m.userLocation?.location else { return }
        m.userTrackingMode = .none
        m.setCenter(loc.coordinate, animated: true)
    }
}
