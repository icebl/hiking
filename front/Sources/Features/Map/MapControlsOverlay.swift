import SwiftUI

/// 地图悬浮控件叠加层（轨迹详情地图复用）：
///   右列：图层(占位) / 工具(占位) / 缩放± / 滑块 / 公里标
///   左列：回到原点（重新框住轨迹）
struct MapControlsOverlay: View {
    @ObservedObject var controller: MapController
    @Binding var showKm: Bool
    var showContours: Bool = false
    var hasProfile: Bool = false
    var showProfile: Bool = false
    /// 路网开关（仅离线矢量底图有效）；showRoadNetwork 绑定，isVectorBase 控制是否显示该控件。
    var isVectorBase: Bool = false
    @Binding var showRoadNetwork: Bool
    var onPlaceholder: (String) -> Void = { _ in }
    var onLayers: () -> Void = {}
    var onContours: () -> Void = {}
    var onProfile: () -> Void = {}

    var body: some View {
        ZStack {
            // 右列
            HStack {
                Spacer()
                VStack(spacing: 14) {
                    ctrl("square.3.stack.3d", "图层") { onLayers() }
                    ctrl("wrench.and.screwdriver", "工具") { onPlaceholder("工具箱后续开放") }
                    Spacer()
                    zoomGroup
                    zoomSlider
                    Spacer()
                    ctrl("ruler", "公里标", active: showKm) { showKm.toggle() }
                    ctrl("mountain.2", "等高线", active: showContours) { onContours() }
                    if isVectorBase {
                        ctrl("point.topleft.down.curvedto.point.bottomright.up", "路网",
                             active: showRoadNetwork) { showRoadNetwork.toggle() }
                    }
                    if hasProfile {
                        ctrl("chart.xyaxis.line", "剖面", active: showProfile) { onProfile() }
                    }
                }
            }
            .padding(.trailing, 14).padding(.vertical, 16)

            // 左列：回到原点
            HStack {
                VStack {
                    Spacer()
                    ctrl("scope", "回到原点") { controller.fitTrack() }
                    Spacer()
                }
                Spacer()
            }
            .padding(.leading, 14).padding(.vertical, 16)
        }
    }

    private var zoomGroup: some View {
        VStack(spacing: 0) {
            Button { controller.zoomIn() } label: {
                Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppColor.ink).frame(width: 44, height: 44)
            }
            Rectangle().fill(AppColor.divider).frame(width: 44, height: 1)
            Button { controller.zoomOut() } label: {
                Image(systemName: "minus").font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppColor.ink).frame(width: 44, height: 44)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }

    private var zoomSlider: some View {
        let frac = (controller.maxZoom - controller.minZoom) > 0
            ? (controller.zoom - controller.minZoom) / (controller.maxZoom - controller.minZoom) : 0.5
        return ZStack(alignment: .top) {
            Capsule().fill(Color.white.opacity(0.6)).frame(width: 4, height: 110)
            Circle().fill(AppColor.primary).frame(width: 24, height: 24)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                .offset(y: CGFloat(1 - min(1, max(0, frac))) * 86)
        }
        .frame(width: 24, height: 110)
        .contentShape(Rectangle())
        .gesture(DragGesture().onChanged { v in
            controller.setZoom(fraction: 1 - Double(v.location.y) / 110)
        })
    }

    private func ctrl(_ icon: String, _ label: String, active: Bool = false,
                      action: @escaping () -> Void) -> some View {
        VStack(spacing: 3) {
            Button(action: action) {
                Image(systemName: icon).font(.system(size: 18, weight: .regular))
                    .foregroundColor(active ? AppColor.primary : AppColor.ink)
                    .frame(width: 44, height: 44)
                    .background(Color.white).clipShape(Circle())
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            }
            Text(label).font(.system(size: 9, weight: .medium)).foregroundColor(.white)
                .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
        }
    }
}
