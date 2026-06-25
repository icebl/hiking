import Foundation
import CoreLocation

/// 沿轨迹导航核心计算（任务 4.1~4.3）：投影到计划线、剩余里程、偏航判定（防抖+滞回+自交单调窗口）。
final class NavigationEngine {

    struct PlannedLine {
        let points: [CLLocationCoordinate2D]
        let cumulativeDistance: [Double]   // 预计算逐点累计距离（任务 4.2）
        let totalDistance: Double
        let cumulativeAscent: [Double]
        var totalAscent: Double { cumulativeAscent.last ?? 0 }
    }

    /// 由轨迹点构建计划线（任务 4.2）：累计距离/爬升预计算；reverse 反向导航。
    static func buildLine(points: [TrackPoint], reverse: Bool) -> PlannedLine {
        let ordered = reverse ? Array(points.reversed()) : points
        let coords = ordered.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        var cumDist: [Double] = []
        var cumAsc: [Double] = []
        var dAcc = 0.0, aAcc = 0.0
        var prev: CLLocation?
        var lastEle: Double?
        let ascentThreshold = 5.0
        for p in ordered {
            let loc = CLLocation(latitude: p.lat, longitude: p.lon)
            if let prev { dAcc += loc.distance(from: prev) }
            prev = loc
            if let e = p.elevation {
                if let le = lastEle, abs(e - le) >= ascentThreshold {
                    if e > le { aAcc += e - le }
                    lastEle = e
                } else if lastEle == nil { lastEle = e }
            }
            cumDist.append(dAcc)
            cumAsc.append(aAcc)
        }
        return PlannedLine(points: coords, cumulativeDistance: cumDist,
                           totalDistance: dAcc, cumulativeAscent: cumAsc)
    }

    // 偏航阈值（任务 4.3，默认 25m，可在设置覆盖；滞回解除 15m）
    var offRouteThreshold: CLLocationDistance = 25
    var clearThreshold: CLLocationDistance = 15
    var offRouteSustainSeconds: TimeInterval = 10

    private(set) var isOffRoute = false
    private(set) var lastMatchedIndex = 0      // 单调推进窗口，处理自交/之字形（任务 4.3）
    private var offRouteSince: Date?

    /// 输入当前位置，返回到计划线的距离与是否偏航。
    func update(current: CLLocation, line: PlannedLine, accuracyGood: Bool, now: Date = Date()) -> (distanceToLine: Double, progress: Double) {
        // TODO(4.3): 在 [lastMatchedIndex - W, lastMatchedIndex + W] 窗口内求最近线段，更新 lastMatchedIndex
        let (dist, matchedIndex, along) = nearestOnLine(current.coordinate, line: line)
        lastMatchedIndex = matchedIndex

        // 定位差时暂停偏航判定（任务 4.6）
        guard accuracyGood else { return (dist, along) }

        if dist > offRouteThreshold {
            if offRouteSince == nil { offRouteSince = now }
            if let s = offRouteSince, now.timeIntervalSince(s) >= offRouteSustainSeconds {
                isOffRoute = true   // → 触发提醒（任务 4.4）
            }
        } else if dist < clearThreshold {
            offRouteSince = nil
            isOffRoute = false
        }
        return (dist, along)
    }

    /// 最近点投影（占位实现，后续用窗口化与精确投影替换）。
    private func nearestOnLine(_ p: CLLocationCoordinate2D, line: PlannedLine) -> (Double, Int, Double) {
        var best = Double.greatestFiniteMagnitude
        var idx = 0
        for (i, c) in line.points.enumerated() {
            let d = CLLocation(latitude: c.latitude, longitude: c.longitude)
                .distance(from: CLLocation(latitude: p.latitude, longitude: p.longitude))
            if d < best { best = d; idx = i }
        }
        let along = line.cumulativeDistance.indices.contains(idx) ? line.cumulativeDistance[idx] : 0
        return (best, idx, along)
    }

    func remaining(line: PlannedLine, progress: Double) -> Double { max(0, line.totalDistance - progress) }
}
