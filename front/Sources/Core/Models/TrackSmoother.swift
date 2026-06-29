import Foundation
import CoreLocation

/// 轨迹平滑去噪（纯函数，非破坏）：对 GPS 水平抖动与海拔毛刺做滤波，
/// 改善里程/爬升统计与轨迹观感。原始轨迹始终保留——平滑结果由
/// `TrackEditor.smoothSave` 另存为新轨迹（符合 PRD「记录原始轨迹，提供平滑/去噪」）。
///
/// 处理按 `segment` 分段进行（不跨断段平滑，断段两端本就不连线），每段三步：
///   ① 速度离群点剔除：相邻点推算速度过高 → 判为 GPS 跳点丢弃；
///   ② 位置居中滑动平均：对 lat/lon 各做窗口平均，去掉静止/缓行时的来回抖动（也修正其造成的里程虚增）；
///   ③ 海拔中值滤波 + 滑动平均：先去尖峰再去抖，显著改善爬升累计的真实性。
enum TrackSmoother {
    // —— 调参（中等强度，徒步场景）——
    private static let posWindow = 5            // 位置滑动平均窗口（奇数，居中）
    private static let eleMedianWindow = 5      // 海拔中值滤波窗口（去尖峰）
    private static let eleMeanWindow = 3        // 海拔滑动平均窗口（去抖）
    private static let maxSpeed: CLLocationDistance = 12.0  // 相邻点推算速度上限(m/s≈43km/h)，超过判为漂移跳点

    /// 对整条轨迹平滑：保持原 segment 分组、组内按 seq 排序，分别处理后按段序拼回。
    static func smooth(_ points: [TrackPoint]) -> [TrackPoint] {
        guard points.count > 2 else { return points }
        let groups = Dictionary(grouping: points, by: { $0.segment })
        var out: [TrackPoint] = []
        for key in groups.keys.sorted() {
            let seg = groups[key]!.sorted { $0.seq < $1.seq }
            out.append(contentsOf: smoothSegment(seg))
        }
        return out
    }

    /// 单段平滑：剔离群点 → 位置滑动平均 → 海拔中值+滑动平均。
    private static func smoothSegment(_ seg: [TrackPoint]) -> [TrackPoint] {
        guard seg.count > 2 else { return seg }          // 点太少不处理，直接原样返回
        var pts = dropOutliers(seg)
        smoothPositions(&pts)
        smoothElevations(&pts)
        return pts
    }

    /// 速度离群点剔除：相邻（与上一保留点）推算速度超过 maxSpeed 视为 GPS 跳点丢弃；
    /// 仅在两点都有时间戳且间隔为正时启用速度判据，否则保留该点（避免误删无时间戳数据）。
    private static func dropOutliers(_ seg: [TrackPoint]) -> [TrackPoint] {
        guard seg.count > 2 else { return seg }
        var kept: [TrackPoint] = [seg[0]]                // 首点恒保留
        for i in 1..<seg.count {
            let a = kept.last!, b = seg[i]
            if let ta = a.timestamp, let tb = b.timestamp, tb > ta {
                let d = CLLocation(latitude: a.lat, longitude: a.lon)
                    .distance(from: CLLocation(latitude: b.lat, longitude: b.lon))
                if d / tb.timeIntervalSince(ta) > maxSpeed { continue }   // 跳点：丢弃
            }
            kept.append(b)
        }
        return kept
    }

    /// 位置居中滑动平均：用平滑前的原始坐标快照做窗口平均，去抖；首尾各半窗保持不动（保起终点保真）。
    private static func smoothPositions(_ pts: inout [TrackPoint]) {
        let n = pts.count
        guard n > posWindow else { return }
        let half = posWindow / 2
        let srcLat = pts.map { $0.lat }, srcLon = pts.map { $0.lon }   // 先快照，避免边算边覆盖
        for i in half..<(n - half) {
            var sLat = 0.0, sLon = 0.0
            for j in (i - half)...(i + half) { sLat += srcLat[j]; sLon += srcLon[j] }
            pts[i].lat = sLat / Double(posWindow)
            pts[i].lon = sLon / Double(posWindow)
        }
    }

    /// 海拔去噪：仅取有海拔的点压成序列，先中值滤波去尖峰、再滑动平均去抖，写回原位置；无海拔的点不动。
    private static func smoothElevations(_ pts: inout [TrackPoint]) {
        let idx = pts.indices.filter { pts[$0].elevation != nil }
        guard idx.count > eleMedianWindow else { return }
        var vals = idx.map { pts[$0].elevation! }
        vals = medianFilter(vals, window: eleMedianWindow)
        vals = meanFilter(vals, window: eleMeanWindow)
        for (k, i) in idx.enumerated() { pts[i].elevation = vals[k] }
    }

    /// 中值滤波（居中窗口，边缘自动缩小窗口）。中值对单点尖峰最稳健。
    private static func medianFilter(_ a: [Double], window: Int) -> [Double] {
        guard a.count >= window, window > 1 else { return a }
        let half = window / 2
        var out = a
        for i in a.indices {
            let lo = max(0, i - half), hi = min(a.count - 1, i + half)
            let slice = a[lo...hi].sorted()
            out[i] = slice[slice.count / 2]
        }
        return out
    }

    /// 滑动平均（居中窗口，边缘自动缩小窗口）。
    private static func meanFilter(_ a: [Double], window: Int) -> [Double] {
        guard a.count >= window, window > 1 else { return a }
        let half = window / 2
        var out = a
        for i in a.indices {
            let lo = max(0, i - half), hi = min(a.count - 1, i + half)
            var s = 0.0
            for j in lo...hi { s += a[j] }
            out[i] = s / Double(hi - lo + 1)
        }
        return out
    }
}
