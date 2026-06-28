import SwiftUI

/// 比例尺标尺：按地图当前「米/点」选一个整数距离(1/2/5×10ⁿ)画横条+标签，随缩放/平移刷新。
/// 依赖 controller.zoom / centerLat（@Published）触发重算。
struct ScaleBarView: View {
    @ObservedObject var controller: MapController
    @AppStorage("highContrastMap") private var highContrast = false   // 高对比：标签加深色底
    private let maxWidth: CGFloat = 90   // 标尺最大宽度（点），实际取不超过它的整数距离

    var body: some View {
        // 读 zoom/centerLat 仅为建立依赖触发刷新；实际米/点取 MapLibre 计算值
        _ = controller.zoom; _ = controller.centerLat
        let mpp = controller.metersPerPoint()
        return Group {
            if mpp > 0 {
                let meters = Self.niceDistance(mpp * Double(maxWidth))
                let width = CGFloat(meters / mpp)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.label(meters))
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, highContrast ? 6 : 0).padding(.vertical, highContrast ? 2 : 0)
                        .background(highContrast ? AppColor.mapScrim(true) : Color.clear)
                        .cornerRadius(6)
                    // 标尺：底横线 + 两端竖线
                    ZStack(alignment: .bottom) {
                        HStack(spacing: 0) {
                            Rectangle().frame(width: 2, height: 7)
                            Spacer()
                            Rectangle().frame(width: 2, height: 7)
                        }
                        Rectangle().frame(height: 2)
                    }
                    .frame(width: max(2, width), height: 7).foregroundColor(.white)
                }
                .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
            }
        }
    }

    /// 取 ≤ maxMeters 的最大「1/2/5×10ⁿ」整数距离。
    static func niceDistance(_ maxMeters: Double) -> Double {
        guard maxMeters > 0 else { return 1 }
        let p = pow(10, floor(log10(maxMeters)))
        let f = maxMeters / p
        return (f >= 5 ? 5 : (f >= 2 ? 2 : 1)) * p
    }
    /// 距离文本：≥1000m 用 km。
    static func label(_ m: Double) -> String {
        m >= 1000 ? "\(Int(m / 1000)) km" : "\(Int(m)) m"
    }
}

/// 指北针：地图旋转(direction≠0)时显示，点击复位正北。指针随 bearing 反向旋转始终指北。
struct CompassButton: View {
    @ObservedObject var controller: MapController
    var body: some View {
        if abs(controller.bearing) > 0.5 {
            Button { controller.resetNorth() } label: {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppColor.recording)
                    .rotationEffect(.degrees(-controller.bearing))   // 抵消地图旋转，指针恒指北
                    .frame(width: 40, height: 40)
                    .background(Color.white).clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
        }
    }
}
