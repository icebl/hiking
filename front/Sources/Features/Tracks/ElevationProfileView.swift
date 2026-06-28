import SwiftUI
import Charts
import CoreLocation

/// 海拔剖面采样点：沿轨迹累计距离(km) + 海拔(m) + 坐标（联动地图用）+ 坡度(%)。
/// 坡度 = 相对上一采样的「海拔差 ÷ 水平距离 ×100」，正为上坡、负为下坡（首点为 0）。
struct ElevSample: Identifiable {
    let id: Int
    let d: Double          // 累计距离 km
    let ele: Double        // 海拔 m
    let coord: CLLocationCoordinate2D
    let slope: Double      // 坡度百分比（带符号），新字段追加在末尾
}

/// 坡度分级（按 |坡度%|）：缓 / 中 / 陡 / 极陡。用于剖面着色与图例，徒步友好阈值。
enum SlopeGrade: String, CaseIterable {
    case easy = "缓", moderate = "中", steep = "陡", extreme = "极陡"

    /// 按坡度绝对值归级（上下坡同级，方向只体现在读数符号上）。
    static func of(_ slopePercent: Double) -> SlopeGrade {
        switch abs(slopePercent) {
        case ..<10:  return .easy        // 缓坡：<10%
        case ..<20:  return .moderate    // 中坡：10–20%
        case ..<30:  return .steep       // 陡坡：20–30%
        default:     return .extreme     // 极陡：≥30%
        }
    }

    /// 分级配色：绿→黄→橙→红，强度随坡度递增。
    var color: Color {
        switch self {
        case .easy:     return Color(.systemGreen)
        case .moderate: return Color(.systemYellow)
        case .steep:    return Color(.systemOrange)
        case .extreme:  return Color(.systemRed)
        }
    }
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
                    // 选中点：距离 · 海拔 · 坡度（带符号，正上坡/负下坡）
                    Text(String(format: "%.2f km · %.0f m · 坡度 %+.0f%%",
                                samples[i].d, samples[i].ele, samples[i].slope))
                        .font(.caption).foregroundColor(AppColor.primary)
                } else {
                    // 概览：全程 · 累计爬升 · 最陡坡度
                    Text(String(format: "全程 %.2f km · 爬升 %.0f m · 最陡 %.0f%%",
                                totalKm, totalAscent, maxSlope))
                        .font(.caption).foregroundColor(AppColor.ink2)
                }
            }
            chart
            legend
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
    /// 全程最陡坡度（取 |坡度| 最大值，概览展示用）。
    private var maxSlope: Double { samples.map { abs($0.slope) }.max() ?? 0 }

    /// 坡度分级图例：四档色点 + 文案 + 阈值，帮助理解剖面着色含义。
    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(SlopeGrade.allCases, id: \.self) { g in
                HStack(spacing: 4) {
                    Circle().fill(g.color).frame(width: 8, height: 8)
                    Text(g.rawValue).font(.system(size: 10)).foregroundColor(AppColor.ink2)
                }
            }
            Spacer()
            Text("缓<10% · 中<20% · 陡<30% · 极陡≥30%")
                .font(.system(size: 9)).foregroundColor(AppColor.ink2.opacity(0.7))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.top, 2)
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
                    .interpolationMethod(.monotone)
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
        // 覆盖层：底部坡度色带（Canvas 用 proxy 精确对齐 x 轴，逐段按坡度上色）+ 拖动捕获
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plot = geo[proxy.plotAreaFrame]
                ZStack(alignment: .topLeading) {
                    // 坡度色带：贴在绘图区底部的细条，每段（相邻采样间）按其坡度等级着色
                    Canvas { ctx, _ in
                        guard samples.count > 1 else { return }
                        let bandH: CGFloat = 6
                        let y = plot.maxY - bandH
                        for i in 1..<samples.count {
                            guard let x0 = proxy.position(forX: samples[i - 1].d),
                                  let x1 = proxy.position(forX: samples[i].d) else { continue }
                            let rect = CGRect(x: plot.origin.x + x0, y: y,
                                              width: max(1, x1 - x0), height: bandH)
                            ctx.fill(Path(roundedRect: rect, cornerRadius: 0),
                                     with: .color(SlopeGrade.of(samples[i].slope).color))
                        }
                    }
                    // 透明层捕获拖动：把手指 x 像素换算成距离值，再就近吸附到采样点
                    Rectangle().fill(Color.clear).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                            let x = v.location.x - plot.origin.x   // 减去绘图区原点，得相对 x
                            if let d: Double = proxy.value(atX: x) { selected = nearestIndex(to: d) }
                        })
                }
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
