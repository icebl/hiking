import XCTest
import CoreLocation
@testable import Hiking

/// CoordFormatter（坐标格式化）单元测试。
final class CoordFormatterTests: XCTestCase {
    private let c = CLLocationCoordinate2D(latitude: 41.69500, longitude: 123.34430)

    /// 十进制度：含 °N/°E。
    func testDecimal() {
        XCTAssertEqual(CoordFormatter.decimal(c), "41.69500°N 123.34430°E")
    }

    /// 纯十进制 "纬, 经"：英文逗号+空格，无 °/N/E。
    func testDecimalPlain() {
        XCTAssertEqual(CoordFormatter.decimalPlain(c), "41.69500, 123.34430")
    }

    /// 南/西半球带 S/W。
    func testSouthWest() {
        let sw = CLLocationCoordinate2D(latitude: -12.5, longitude: -77.0)
        XCTAssertEqual(CoordFormatter.decimal(sw), "12.50000°S 77.00000°W")
    }

    /// 度分秒格式形如 41°41'42.0"N …。
    func testDMS() {
        let s = CoordFormatter.dms(c)
        XCTAssertTrue(s.contains("°"))
        XCTAssertTrue(s.contains("'"))
        XCTAssertTrue(s.hasSuffix("E") || s.contains("E "))
        XCTAssertTrue(s.contains("N"))
    }

    /// string(_:format:) 分派：未知格式回落十进制度。
    func testDispatchFallback() {
        XCTAssertEqual(CoordFormatter.string(c, format: "未知格式"), CoordFormatter.decimal(c))
        XCTAssertEqual(CoordFormatter.string(c, format: "十进制 lat, lon"), CoordFormatter.decimalPlain(c))
    }
}
