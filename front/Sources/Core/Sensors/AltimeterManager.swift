import Foundation
import CoreMotion
import Combine

/// 气压计海拔（任务 3.4）：设备支持时优先用气压相对高度，否则回退 GPS 海拔。
final class AltimeterManager: ObservableObject {
    private let altimeter = CMAltimeter()   // 系统气压计接口

    @Published var relativeAltitude: Double?   // 米（相对 start() 时刻起点，非绝对海拔）
    @Published var pressure: Double?            // kPa（当前大气压）

    /// 设备是否支持相对高度（无气压计的机型返回 false）
    static var isAvailable: Bool { CMAltimeter.isRelativeAltitudeAvailable() }

    /// 开始气压高度更新；回调在主线程驱动 @Published 属性。不可用时静默返回。
    func start() {
        guard Self.isAvailable else { return }   // 不可用则交由 GPS 海拔
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let data else { return }   // 忽略无数据/出错的回调
            self?.relativeAltitude = data.relativeAltitude.doubleValue
            self?.pressure = data.pressure.doubleValue
        }
    }

    /// 停止更新（相对高度基准随之失效，下次 start 重新以新位置为起点）
    func stop() { altimeter.stopRelativeAltitudeUpdates() }
}
