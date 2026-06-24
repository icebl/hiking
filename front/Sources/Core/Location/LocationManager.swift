import Foundation
import CoreLocation
import Combine

/// 定位管理：前台/后台连续定位 + 朝向（任务 3.1 / 3.2 / 4.x）。
/// 后台记录是生死线：Background Modes=location + Always 权限 + allowsBackgroundLocationUpdates。
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    private let manager = CLLocationManager()

    @Published var location: CLLocation?
    @Published var heading: CLLocationDirection = 0      // 朝向（个人位置箭头用，任务 4 / 地图箭头）
    @Published var authorization: CLAuthorizationStatus = .notDetermined

    // 采样过滤参数（任务 3.3，默认 5s + 5m 在采样层处理；此处设最小距离过滤）
    var minDistanceFilter: CLLocationDistance = 5

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = minDistanceFilter
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
    }

    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }
    func requestAlways() { manager.requestAlwaysAuthorization() }

    /// 开始（后台）连续定位。
    func start(background: Bool) {
        if background {
            // 仅在已授予 Always 时允许后台更新，否则会崩溃。
            manager.allowsBackgroundLocationUpdates = (authorization == .authorizedAlways)
            manager.showsBackgroundLocationIndicator = true
        }
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        manager.allowsBackgroundLocationUpdates = false
    }

    // MARK: - CLLocationManagerDelegate
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        // TODO(3.6): 低精度点丢弃（horizontalAccuracy 过大）、最小位移过滤、静止降频
        location = loc
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // TODO(3.x): 错误处理 / 定位较差状态
    }
}
