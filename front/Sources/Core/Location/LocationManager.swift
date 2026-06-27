import Foundation
import CoreLocation
import Combine

/// 定位管理：前台/后台连续定位 + 朝向（任务 3.1 / 3.2 / 4.x）。
/// 后台记录是生死线：Background Modes=location + Always 权限 + allowsBackgroundLocationUpdates。
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()   // 全局单例，定位状态全局共享

    private let manager = CLLocationManager()

    @Published var location: CLLocation?                 // 最近一次定位（nil 表示尚未定到位）
    @Published var heading: CLLocationDirection = 0      // 朝向，单位度 0~360（个人位置箭头用，任务 4 / 地图箭头）
    @Published var authorization: CLAuthorizationStatus = .notDetermined   // 当前定位授权状态

    // 采样过滤参数（任务 3.3，默认 5s + 5m 在采样层处理；此处设最小距离过滤）
    var minDistanceFilter: CLLocationDistance = 5

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest   // 徒步需最高精度
        manager.distanceFilter = minDistanceFilter
        manager.activityType = .fitness                     // 健身场景，系统据此优化功耗/算法
        manager.pausesLocationUpdatesAutomatically = false  // 关闭自动暂停，防止久站后丢点
    }

    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }   // 申请「使用期间」权限
    func requestAlways() { manager.requestAlwaysAuthorization() }         // 申请「始终」权限（后台记录所需）

    /// 已授权（前台或始终）
    var allowed: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }
    /// 被拒绝/受限（需引导去设置）
    var denied: Bool { authorization == .denied || authorization == .restricted }

    /// 开始连续定位与朝向更新。
    /// - Parameter background: 是否需要后台持续记录（轨迹记录场景传 true）。
    func start(background: Bool) {
        applyPowerMode()   // 按「省电定位」设置调精度/位移过滤（每次 start 读最新设置）
        if background {
            // 仅在已授予 Always 时允许后台更新，否则会崩溃。
            manager.allowsBackgroundLocationUpdates = (authorization == .authorizedAlways)
            manager.showsBackgroundLocationIndicator = true   // 显示系统蓝色后台定位指示条
        }
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    /// 省电定位：开启则降精度(~10m)+加大最小位移(10m)，显著省电、轨迹略糙；关闭走最高精度。
    /// 供真机续航实测 A/B 对比；每次 start 时按最新设置应用。
    private func applyPowerMode() {
        if AppSettings.powerSaveGPS {
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            manager.distanceFilter = 10
        } else {
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = minDistanceFilter
        }
    }

    /// 停止定位与朝向，并关闭后台更新开关
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
        // 优先真北朝向；trueHeading<0 表示无效（无定位校准），退回磁北
        heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // TODO(3.x): 错误处理 / 定位较差状态
    }
}
