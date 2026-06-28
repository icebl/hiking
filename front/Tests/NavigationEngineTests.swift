import XCTest
import CoreLocation
@testable import Hiking

/// NavigationEngine（计划线/投影/偏航滞回）单元测试。
final class NavigationEngineTests: XCTestCase {

    /// 造一条沿经度 0、纬度递增的直线轨迹点。
    private func point(_ lat: Double, _ lon: Double, _ seq: Int, ele: Double? = nil) -> TrackPoint {
        TrackPoint(id: nil, trackId: UUID(), segment: 0, seq: seq,
                   lat: lat, lon: lon, elevation: ele, timestamp: nil, speed: nil, horizontalAccuracy: nil)
    }

    private func straightLine() -> NavigationEngine.PlannedLine {
        let pts = [point(0.000, 0, 0), point(0.001, 0, 1), point(0.002, 0, 2)]  // 每段≈111m
        return NavigationEngine.buildLine(points: pts, reverse: false)
    }

    /// buildLine：累计距离递增、总长≈两段之和。
    func testBuildLine() {
        let line = straightLine()
        XCTAssertEqual(line.points.count, 3)
        XCTAssertEqual(line.cumulativeDistance[0], 0, accuracy: 0.1)
        XCTAssertGreaterThan(line.cumulativeDistance[1], line.cumulativeDistance[0])
        XCTAssertGreaterThan(line.cumulativeDistance[2], line.cumulativeDistance[1])
        XCTAssertEqual(line.totalDistance, 222, accuracy: 10)   // ≈ 2×111m
    }

    /// 反向：首末点对调。
    func testReverse() {
        let pts = [point(0, 0, 0), point(0.001, 0, 1)]
        let line = NavigationEngine.buildLine(points: pts, reverse: true)
        XCTAssertEqual(line.points.first!.latitude, 0.001, accuracy: 1e-9)
        XCTAssertEqual(line.points.last!.latitude, 0.0, accuracy: 1e-9)
    }

    /// 线上点：垂距≈0，不偏航。
    func testOnLineNotOffRoute() {
        let engine = NavigationEngine()
        let line = straightLine()
        let onLine = CLLocation(latitude: 0.001, longitude: 0)
        let (dist, _) = engine.update(current: onLine, line: line, accuracyGood: true, now: Date())
        XCTAssertLessThan(dist, 5)
        XCTAssertFalse(engine.isOffRoute)
    }

    /// 偏航滞回：远离点需「持续超阈值 10s」才判偏航——首帧不判，11s 后判。
    func testOffRouteHysteresis() {
        let engine = NavigationEngine()
        let line = straightLine()
        let far = CLLocation(latitude: 0.001, longitude: 0.001)   // ≈111m 偏离
        let t0 = Date()
        let (dist, _) = engine.update(current: far, line: line, accuracyGood: true, now: t0)
        XCTAssertGreaterThan(dist, 25)
        XCTAssertFalse(engine.isOffRoute, "首次越界不应立即判偏航")
        _ = engine.update(current: far, line: line, accuracyGood: true, now: t0.addingTimeInterval(11))
        XCTAssertTrue(engine.isOffRoute, "持续超阈值 10s 后应判偏航")
    }

    /// 精度差时暂停偏航判定。
    func testBadAccuracySkips() {
        let engine = NavigationEngine()
        let line = straightLine()
        let far = CLLocation(latitude: 0.001, longitude: 0.01)
        _ = engine.update(current: far, line: line, accuracyGood: false, now: Date())
        XCTAssertFalse(engine.isOffRoute)
    }
}
