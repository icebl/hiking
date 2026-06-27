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

    // 投影匹配窗口（任务 4.3）：每帧只在 lastMatchedIndex 附近搜索线段，处理自交/之字形/折返，
    // 兼顾前进（更大向前窗口）与少量回退/GPS 抖动；偏离过远时回退全线重捕获（re-acquire）。
    var matchBackWindow = 8         // 向后可搜索的线段数（应对回退/抖动）
    var matchForwardWindow = 40     // 向前可搜索的线段数（前进方向给更大窗口）

    private(set) var isOffRoute = false
    private(set) var lastMatchedIndex = 0      // 上次命中的线段起点下标，作为下帧窗口锚点（任务 4.3）
    private var offRouteSince: Date?           // 首次超阈值时刻；用于累计持续时长

    /// 输入当前位置，返回(到计划线最近距离, 沿线进度)，并更新 isOffRoute 偏航状态。
    /// - 副作用：更新 lastMatchedIndex / offRouteSince / isOffRoute。
    func update(current: CLLocation, line: PlannedLine, accuracyGood: Bool, now: Date = Date()) -> (distanceToLine: Double, progress: Double) {
        // 窗口化最近线段投影：dist=到计划线垂距，along=沿线进度（见 nearestOnLine）
        let (dist, matchedIndex, along) = nearestOnLine(current.coordinate, line: line)
        lastMatchedIndex = matchedIndex   // 更新窗口锚点，供下一帧就近搜索

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

    /// 最近线段投影（窗口化 + 偏远时全线重捕获）。
    /// 返回 (到计划线垂直距离 m, 命中线段起点下标, 沿线累计进度 m)。
    /// 相比旧「最近顶点」实现：稀疏轨迹点下偏航距离更准、进度连续不跳变；窗口化避免自交/折返误匹配到远处同名段。
    private func nearestOnLine(_ p: CLLocationCoordinate2D, line: PlannedLine) -> (Double, Int, Double) {
        let n = line.points.count
        guard n >= 2 else {
            // 退化：0 或 1 个点无法成段，回退到点距（或 0）
            guard let only = line.points.first else { return (0, 0, 0) }
            let d = CLLocation(latitude: only.latitude, longitude: only.longitude)
                .distance(from: CLLocation(latitude: p.latitude, longitude: p.longitude))
            return (d, 0, 0)
        }
        // 线段下标范围 0...n-2；先在锚点附近窗口内搜
        let lo = max(0, lastMatchedIndex - matchBackWindow)
        let hi = min(n - 2, lastMatchedIndex + matchForwardWindow)
        var best = searchSegments(p, line: line, range: lo...hi)
        // 窗口内最优仍偏远（偏航/丢失/折返到远处）→ 全线重捕获，取更近者
        let reacquire = max(50, offRouteThreshold * 2)
        if best.dist > reacquire {
            let global = searchSegments(p, line: line, range: 0...(n - 2))
            if global.dist < best.dist { best = global }
        }
        return (best.dist, best.index, best.along)
    }

    /// 在给定线段下标区间内逐段投影，取垂距最小的一段。
    /// 返回 (最小垂距 m, 命中线段起点下标, 沿线累计进度 m = 段起点累计距离 + 投影点在本段长度)。
    private func searchSegments(_ p: CLLocationCoordinate2D, line: PlannedLine,
                                range: ClosedRange<Int>) -> (dist: Double, index: Int, along: Double) {
        func cum(_ i: Int) -> Double { line.cumulativeDistance.indices.contains(i) ? line.cumulativeDistance[i] : 0 }
        var bestDist = Double.greatestFiniteMagnitude
        var bestIndex = range.lowerBound
        var bestAlong = 0.0
        for i in range {
            let (t, d) = projectPointToSegment(p, line.points[i], line.points[i + 1])
            if d < bestDist {
                bestDist = d
                bestIndex = i
                bestAlong = cum(i) + t * (cum(i + 1) - cum(i))   // 段内按投影比例插值累计距离
            }
        }
        return (bestDist, bestIndex, bestAlong)
    }

    /// 把点 P 投影到线段 A-B（以 A 为原点的局部等距平面近似；线段短，足够精确）。
    /// 返回 (投影参数 t∈[0,1]，0=A 端、1=B 端；P 到投影点的距离 m)。
    private func projectPointToSegment(_ p: CLLocationCoordinate2D,
                                       _ a: CLLocationCoordinate2D,
                                       _ b: CLLocationCoordinate2D) -> (t: Double, dist: Double) {
        // 经度每度米数随纬度收缩，用 A 的纬度换算；纬度每度约 111320m
        let mPerLat = 111_320.0
        let mPerLon = 111_320.0 * cos(a.latitude * .pi / 180)
        let bx = (b.longitude - a.longitude) * mPerLon, by = (b.latitude - a.latitude) * mPerLat
        let px = (p.longitude - a.longitude) * mPerLon, py = (p.latitude - a.latitude) * mPerLat
        let segLen2 = bx * bx + by * by
        // 投影比例 t = (AP·AB)/|AB|²，夹到 [0,1] 落在线段内；零长线段取端点
        let t = segLen2 > 0 ? max(0, min(1, (px * bx + py * by) / segLen2)) : 0
        let cx = t * bx, cy = t * by                       // 投影点（相对 A 的平面坐标）
        return (t, hypot(px - cx, py - cy))
    }

    func remaining(line: PlannedLine, progress: Double) -> Double { max(0, line.totalDistance - progress) }
}
