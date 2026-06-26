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
    let samples: [ElevSample]
    @Binding var selected: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("海拔剖面").font(.caption).foregroundColor(AppColor.ink2)
                Spacer()
                if let i = selected, samples.indices.contains(i) {
                    Text(String(format: "%.2f km · %.0f m", samples[i].d, samples[i].ele))
                        .font(.caption).foregroundColor(AppColor.primary)
                }
            }
            chart
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.white)
    }

    private var chart: some View {
        Chart {
            ForEach(samples) { s in
                AreaMark(x: .value("距离", s.d), y: .value("海拔", s.ele))
                    .foregroundStyle(AppColor.contour.opacity(0.18))
                LineMark(x: .value("距离", s.d), y: .value("海拔", s.ele))
                    .foregroundStyle(AppColor.contour)
                    .interpolationMethod(.monotone)
            }
            if let i = selected, samples.indices.contains(i) {
                RuleMark(x: .value("选中", samples[i].d)).foregroundStyle(AppColor.ink2.opacity(0.5))
                PointMark(x: .value("距离", samples[i].d), y: .value("海拔", samples[i].ele))
                    .foregroundStyle(AppColor.primary)
            }
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 96)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        let origin = geo[proxy.plotAreaFrame].origin
                        let x = v.location.x - origin.x
                        if let d: Double = proxy.value(atX: x) { selected = nearestIndex(to: d) }
                    })
            }
        }
    }

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
