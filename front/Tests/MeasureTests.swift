import XCTest
import CoreLocation
@testable import Hiking

/// Measure（测距/面积/方位）纯逻辑单元测试。
final class MeasureTests: XCTestCase {

    /// 折线总长：赤道上沿纬度走 1° ≈ 111.19 km。
    func testTotalDistance() {
        let pts = [CLLocationCoordinate2D(latitude: 0, longitude: 0),
                   CLLocationCoordinate2D(latitude: 1, longitude: 0)]
        XCTAssertEqual(Measure.totalDistance(pts), 111_194, accuracy: 500)
    }

    /// 不足两点距离为 0。
    func testTotalDistanceTooFew() {
        XCTAssertEqual(Measure.totalDistance([]), 0)
        XCTAssertEqual(Measure.totalDistance([CLLocationCoordinate2D(latitude: 1, longitude: 1)]), 0)
    }

    /// 多边形面积：0.01°×0.01° 小方块（赤道附近），边长≈1113m → 面积≈1.24e6 m²。
    func testPolygonArea() {
        let d = 0.01
        let poly = [CLLocationCoordinate2D(latitude: 0, longitude: 0),
                    CLLocationCoordinate2D(latitude: 0, longitude: d),
                    CLLocationCoordinate2D(latitude: d, longitude: d),
                    CLLocationCoordinate2D(latitude: d, longitude: 0)]
        XCTAssertEqual(Measure.polygonArea(poly), 1_239_000, accuracy: 5e4)
    }

    /// 距离文本：<1km 用米，≥1km 用公里。
    func testDistanceText() {
        XCTAssertEqual(Measure.distanceText(500), "500 m")
        XCTAssertEqual(Measure.distanceText(1500), "1.50 km")
    }

    /// 方位：正北≈0、正东≈90。
    func testBearing() {
        let origin = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let north = CLLocationCoordinate2D(latitude: 1, longitude: 0)
        let east = CLLocationCoordinate2D(latitude: 0, longitude: 1)
        XCTAssertEqual(Measure.bearing(from: origin, to: north), 0, accuracy: 1)
        XCTAssertEqual(Measure.bearing(from: origin, to: east), 90, accuracy: 1)
    }

    /// 八方位中文。
    func testCompass8() {
        XCTAssertEqual(Measure.compass8(0), "北")
        XCTAssertEqual(Measure.compass8(90), "东")
        XCTAssertEqual(Measure.compass8(180), "南")
        XCTAssertEqual(Measure.compass8(270), "西")
        XCTAssertEqual(Measure.compass8(45), "东北")
    }

    /// 圆环点数 = segments+1（首尾相接）。
    func testRingCount() {
        let ring = Measure.ring(center: CLLocationCoordinate2D(latitude: 30, longitude: 120), radius: 500, segments: 64)
        XCTAssertEqual(ring.count, 65)
    }
}
