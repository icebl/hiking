import SwiftUI
import Charts
import CoreLocation

/// 海拔剖面采样点：沿轨迹累计距离(km) + 海拔(m) + 坐标（联动地图用）。
struct ElevSample: Identifiable {
    let id: Int
    let d: Double          // 累计距离 km
    let ele: Double        // 海拔 m
    let coord: CLLocationCoordinate2D
}

/// 海拔剖面图（任务 5.6）：距离-海拔折线 + 拖动选点（联动地图高亮）。
struct ElevationProfileView: View {
    let samples: [ElevSample]          // 下采样后的剖面点（由 TrackDetailView 传入）
    @Binding var selected: Int?        // 选中采样下标（双向绑定，拖动更新→父视图地图高亮）

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("海拔剖面").font(.caption).foregroundColor(AppColor.ink2)
                Spacer()
                if let i = selected, samples.indices.contains(i) {
                    Text(String(format: "%.2f km · %.0f m", samples[i].d, samples[i].ele))
                        .font(.caption).foregroundColor(AppColor.primary)
                } else {
                    Text(String(format: "全程 %.2f km · 累计爬升 %.0f m", totalKm, totalAscent))
                        .font(.caption).foregroundColor(AppColor.ink2)
                }
            }
            chart
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.white)
    }

    /// 全程距离（km）= 最后一个采样的累计距离。
    private var totalKm: Double { samples.last?.d ?? 0 }
    /// 累计爬升（m）= 相邻采样正向海拔差之和。
    private var totalAscent: Double {
        guard samples.count > 1 else { return 0 }
        var sum = 0.0
        for i in 1..<samples.count {
            let d = samples[i].ele - samples[i-1].ele
            if d > 0 { sum += d }
        }
        return sum
    }

    /// Y 轴显示范围：按海拔 min/max 自动缩放（带留白），避免从 0 起把曲线挤在顶部一小条。
    private var yDomain: ClosedRange<Double> {
        let eles = samples.map { $0.ele }
        guard let lo = eles.min(), let hi = eles.max() else { return 0...100 }
        guard hi - lo > 1 else { return (lo - 50)...(hi + 50) }   // 近平地：给固定上下留白
        let pad = max(10, (hi - lo) * 0.12)
        return (lo - pad)...(hi + pad)
    }

    private var chart: some View {
        // 面积图基线取 Y 轴下界（而非 0），让填充贴合自适应后的可视范围
        let base = yDomain.lowerBound
        return Chart {
            ForEach(samples) { s in
                AreaMark(x: .value("距离", s.d),
                         yStart: .value("基线", base),
                         yEnd: .value("海拔", s.ele))
                    .foregroundStyle(AppColor.contour.opacity(0.18))
                LineMark(x: .value("距离", s.d), y: .value("海拔", s.ele))
                    .foregroundStyle(AppColor.contour)
                    .interpolationMethod(.monotone)
            }
            // 有选中点时画竖直标线 + 圆点，与地图高亮形成联动
            if let i = selected, samples.indices.contains(i) {
                RuleMark(x: .value("选中", samples[i].d)).foregroundStyle(AppColor.ink2.opacity(0.5))
                PointMark(x: .value("距离", samples[i].d), y: .value("海拔", samples[i].ele))
                    .foregroundStyle(AppColor.primary)
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 96)
        // 覆盖透明层捕获拖动：把手指 x 像素换算成距离值，再就近吸附到采样点
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        let origin = geo[proxy.plotAreaFrame].origin
                        let x = v.location.x - origin.x   // 减去绘图区原点，得到相对绘图区的 x
                        if let d: Double = proxy.value(atX: x) { selected = nearestIndex(to: d) }
                    })
            }
        }
    }

    /// 找出累计距离最接近 d 的采样下标（线性扫描，返回 id）。
    private func nearestIndex(to d: Double) -> Int? {
        guard !samples.isEmpty else { return nil }
        var best = 0, bestDiff = Double.greatestFiniteMagnitude
        for s in samples {
            let diff = abs(s.d - d)
            if diff < bestDiff { bestDiff = diff; best = s.id }
        }
        return best
    }
}
