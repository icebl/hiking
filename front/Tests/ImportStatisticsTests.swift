import XCTest
import CoreLocation
@testable import Hiking

/// ImportService.statistics（距离/爬升去噪/海拔区间）单元测试。
final class ImportStatisticsTests: XCTestCase {

    private func point(_ lat: Double, _ lon: Double, _ seq: Int, ele: Double?) -> TrackPoint {
        TrackPoint(id: nil, trackId: UUID(), segment: 0, seq: seq,
                   lat: lat, lon: lon, elevation: ele, timestamp: nil, speed: nil, horizontalAccuracy: nil)
    }

    /// 爬升 5m 去噪：海拔 100→103(忽略)→110(+10)→104(-6)。
    /// 期望 ascent=10、descent=6、max=110、min=100。
    func testAscentThreshold() {
        let pts = [point(0.000, 0, 0, ele: 100),
                   point(0.001, 0, 1, ele: 103),
                   point(0.002, 0, 2, ele: 110),
                   point(0.003, 0, 3, ele: 104)]
        let s = ImportService.statistics(of: pts)
        XCTAssertEqual(s.ascent, 10, accuracy: 0.001)
        XCTAssertEqual(s.descent, 6, accuracy: 0.001)
        XCTAssertEqual(s.maxEle ?? -1, 110, accuracy: 0.001)
        XCTAssertEqual(s.minEle ?? -1, 100, accuracy: 0.001)
        XCTAssertGreaterThan(s.distance, 0)
    }

    /// 全程无海拔：max/min 为 nil，爬升 0。
    func testNoElevation() {
        let pts = [point(0, 0, 0, ele: nil), point(0.001, 0, 1, ele: nil)]
        let s = ImportService.statistics(of: pts)
        XCTAssertNil(s.maxEle)
        XCTAssertNil(s.minEle)
        XCTAssertEqual(s.ascent, 0)
    }

    /// 单点：距离 0。
    func testSinglePoint() {
        let s = ImportService.statistics(of: [point(10, 10, 0, ele: 50)])
        XCTAssertEqual(s.distance, 0)
    }
}
