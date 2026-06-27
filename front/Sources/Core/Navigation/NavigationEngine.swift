import Foundation
import CoreLocation

/// 沿轨迹导航核心计算（任务 4.1~4.3）：投影到计划线、剩余里程、偏航判定（防抖+滞回+自交单调窗口）。
final class NavigationEngine {

    /// 预处理后的计划线：与原轨迹点一一对应的累计量缓存，避免每帧重算。
    struct PlannedLine {
        let points: [CLLocationCoordinate2D]
        let cumulativeDistance: [Double]   // 预计算逐点累计距离（米，任务 4.2）
        let totalDistance: Double          // 全线总长（米）
        let cumulativeAscent: [Double]     // 逐点累计爬升（米）
        var totalAscent: Double { cumulativeAscent.last ?? 0 }  // 总爬升 = 末点累计值
    }

    /// 由轨迹点构建计划线（任务 4.2）：累计距离/爬升预计算；reverse 反向导航。
    static func buildLine(points: [TrackPoint], reverse: Bool) -> PlannedLine {
        let ordered = reverse ? Array(points.reversed()) : points
        let coords = ordered.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        var cumDist: [Double] = []
        var cumAsc: [Double] = []
        var dAcc = 0.0, aAcc = 0.0   // 累计距离 / 累计爬升
        var prev: CLLocation?        // 上一点（算相邻距离）
        var lastEle: Double?         // 上一个「有效」高度基准
        let ascentThreshold = 5.0    // 高差阈值：抖动 <5m 不计入爬升，过滤 GPS 高程噪声
        for p in ordered {
            let loc = CLLocation(latitude: p.lat, longitude: p.lon)
            if let prev { dAcc += loc.distance(from: prev) }
            prev = loc
            if let e = p.elevation {
                // 仅当与基准高度差超阈值才更新基准，且只把上升部分计入爬升
                if let le = lastEle, abs(e - le) >= ascentThreshold {
                    if e > le { aAcc += e - le }
                    lastEle = e
                } else if lastEle == nil { lastEle = e }  // 首个高度点作为初始基准
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
    var offRouteSustainSeconds: TimeInterval = 10  // 须持续超阈值 10s 才判偏航，避免瞬时跳点误报

    private(set) var isOffRoute = false
    private(set) var lastMatchedIndex = 0      // 单调推进窗口，处理自交/之字形（任务 4.3）
    private var offRouteSince: Date?           // 首次超阈值时刻；用于累计持续时长

    /// 输入当前位置，返回(到计划线最近距离, 沿线进度)，并更新 isOffRoute 偏航状态。
    /// - 副作用：更新 lastMatchedIndex / offRouteSince / isOffRoute。
    func update(current: CLLocation, line: PlannedLine, accuracyGood: Bool, now: Date = Date()) -> (distanceToLine: Double, progress: Double) {
        // TODO(4.3): 在 [lastMatchedIndex - W, lastMatchedIndex + W] 窗口内求最近线段，更新 lastMatchedIndex
        let (dist, matchedIndex, along) = nearestOnLine(current.coordinate, line: line)
        lastMatchedIndex = matchedIndex

        // 定位差时暂停偏航判定（任务 4.6）
        guard accuracyGood else { return (dist, along) }

        // 滞回判定：进入(>25m 持续 10s)与解除(<15m)用不同阈值，
        // 中间 15~25m 维持现状，避免在阈值附近反复横跳
        if dist > offRouteThreshold {
            if offRouteSince == nil { offRouteSince = now }   // 记录首次越界时刻
            if let s = offRouteSince, now.timeIntervalSince(s) >= offRouteSustainSeconds {
                isOffRoute = true   // 持续超时 → 触发提醒（任务 4.4）
            }
        } else if dist < clearThreshold {
            offRouteSince = nil     // 回到安全带内 → 清零计时并解除偏航
            isOffRoute = false
        }
        return (dist, along)
    }

    /// 最近点投影（占位实现，后续用窗口化与精确投影替换）。
    /// 返回 (到最近顶点距离, 该顶点下标, 沿线累计进度米)。
    /// 注意：当前为「最近顶点」而非「最近线段投影」，且全线遍历未用窗口化（见 update 的 TODO）。
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
