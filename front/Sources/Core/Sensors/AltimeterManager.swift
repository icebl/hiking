import Foundation
import CoreMotion
import Combine

/// 气压计海拔（任务 3.4）：设备支持时优先用气压相对高度，否则回退 GPS 海拔。
final class AltimeterManager: ObservableObject {
    private let altimeter = CMAltimeter()

    @Published var relativeAltitude: Double?   // 米（相对起点）
    @Published var pressure: Double?            // kPa

    static var isAvailable: Bool { CMAltimeter.isRelativeAltitudeAvailable() }

    func start() {
        guard Self.isAvailable else { return }   // 不可用则交由 GPS 海拔
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let data else { return }
            self?.relativeAltitude = data.relativeAltitude.doubleValue
            self?.pressure = data.pressure.doubleValue
        }
    }

    func stop() { altimeter.stopRelativeAltitudeUpdates() }
}
