import Foundation
import CoreLocation

/// 测距/面积计算与格式化（工具箱，原型 §16/17）。
enum Measure {
    /// 折线总长度（米）。
    static func totalDistance(_ coords: [CLLocationCoordinate2D]) -> Double {
        guard coords.count >= 2 else { return 0 }
        var sum = 0.0
        for i in 1..<coords.count {
            sum += CLLocation(latitude: coords[i-1].latitude, longitude: coords[i-1].longitude)
                .distance(from: CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude))
        }
        return sum
    }

    /// 多边形面积（m²）：按质心做局部等距投影后鞋带公式。
    static func polygonArea(_ coords: [CLLocationCoordinate2D]) -> Double {
        guard coords.count >= 3 else { return 0 }
        // 用各点纬度均值作为投影基准纬度，使局部等距投影误差最小
        let lat0 = coords.map { $0.latitude }.reduce(0, +) / Double(coords.count)
        let mPerLat = 111_320.0                          // 每纬度约 111.32km（近似常量）
        let mPerLon = 111_320.0 * cos(lat0 * .pi / 180)  // 每经度随纬度收缩：乘 cos(lat)
        // 经纬度换算成平面米坐标，便于用鞋带公式直接算平面面积
        let pts = coords.map { (x: $0.longitude * mPerLon, y: $0.latitude * mPerLat) }
        var a = 0.0
        // 鞋带公式：累加各边叉积，最后取绝对值除 2（与顶点环绕方向无关）
        for i in 0..<pts.count {
            let j = (i + 1) % pts.count   // 末点回连首点，闭合多边形
            a += pts[i].x * pts[j].y - pts[j].x * pts[i].y
        }
        return abs(a) / 2
    }

    /// 距离文案：<1km 用米（整数），否则用千米（两位小数）。
    static func distanceText(_ m: Double) -> String {
        m < 1000 ? String(format: "%.0f m", m) : String(format: "%.2f km", m / 1000)
    }
    /// 面积文案：按量级自动选单位 m² → 公顷 → km²。
    static func areaText(_ m2: Double) -> String {
        if m2 < 10_000 { return String(format: "%.0f m²", m2) }
        if m2 < 1_000_000 { return String(format: "%.2f 公顷", m2 / 10_000) }
        return String(format: "%.2f km²", m2 / 1_000_000)
    }

    /// 由中心点按方位角(度)+距离(米)求目标点（球面正解，用于画半径圆等）。
    static func destination(_ c: CLLocationCoordinate2D, distance d: Double, bearingDeg b: Double) -> CLLocationCoordinate2D {
        let R = 6_378_137.0   // WGS84 赤道半径（米）
        // 角度转弧度；dr 为角距离（弧长/半径），下方为标准球面正解公式
        let br = b * .pi / 180, lat1 = c.latitude * .pi / 180, lon1 = c.longitude * .pi / 180, dr = d / R
        let lat2 = asin(sin(lat1) * cos(dr) + cos(lat1) * sin(dr) * cos(br))
        let lon2 = lon1 + atan2(sin(br) * sin(dr) * cos(lat1), cos(dr) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }
    /// 以中心生成半径 r(米) 的圆环点（首尾相接）。
    static func ring(center c: CLLocationCoordinate2D, radius r: Double, segments n: Int = 64) -> [CLLocationCoordinate2D] {
        (0...n).map { destination(c, distance: r, bearingDeg: Double($0) / Double(n) * 360) }
    }
}
