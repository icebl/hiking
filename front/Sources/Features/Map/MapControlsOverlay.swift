import SwiftUI

/// 地图悬浮控件叠加层（轨迹详情地图复用）：
///   右列：图层(占位) / 工具(占位) / 缩放± / 滑块 / 公里标
///   左列：回到原点（重新框住轨迹）
struct MapControlsOverlay: View {
    @ObservedObject var controller: MapController   // 复用同一地图控制器，读缩放/定位状态并下发操作
    @State private var zoomDragging = false         // 缩放滑块拖动中（控制左侧数值气泡显隐）
    @Binding var showKm: Bool                       // 公里标开关（由父视图持有）
    var showContours: Bool = false                  // 等高线高亮态（仅显示用，开关动作走 onContours）
    var hasProfile: Bool = false                    // 是否有高程剖面数据，决定剖面控件是否出现
    var showProfile: Bool = false                   // 剖面面板当前是否展开（高亮态）
    /// 路网开关（仅离线矢量底图有效）；showRoadNetwork 绑定，isVectorBase 控制是否显示该控件。
    var isVectorBase: Bool = false
    @Binding var showRoadNetwork: Bool
    /// 标记点显隐开关；hasWaypoints 控制是否显示该控件。
    var hasWaypoints: Bool = false
    @Binding var showWaypoints: Bool
    var toolsActive: Bool = false                   // 工具箱是否激活（测距/面积/雷达/取点中），高亮按钮
    var onTools: () -> Void = {}                    // 点「工具」回调（打开工具箱）
    var onPlaceholder: (String) -> Void = { _ in }  // 占位功能点击回调（如未开放的工具）
    var onLayers: () -> Void = {}                   // 点「图层」回调（切底图，由父视图实现）
    var onContours: () -> Void = {}                 // 点「等高线」回调
    var onProfile: () -> Void = {}                  // 点「剖面」回调（展开/收起剖面面板）

    var body: some View {
        ZStack {
            // 右列：图层 / 工具 / 缩放 / 公里标 / 路网
            HStack {
                Spacer()
                VStack(spacing: 14) {
                    ctrl("square.3.stack.3d", "图层") { onLayers() }
                    ctrl("wrench.and.screwdriver", "工具", active: toolsActive) { onTools() }
                    Spacer()
                    zoomGroup
                    zoomSlider
                    Spacer()
                    ctrl("ruler", "公里标", active: showKm) { showKm.toggle() }
                    if isVectorBase {
                        ctrl("point.topleft.down.curvedto.point.bottomright.up", "路网",
                             active: showRoadNetwork) { showRoadNetwork.toggle() }
                    }
                }
            }
            .padding(.trailing, 14).padding(.vertical, 16)

            // 左列：定位（顶）— 回到原点 / 等高线 / 剖面（中下）
            HStack {
                VStack(spacing: 14) {
                    ctrl(controller.locateState == .off ? "location" : "location.fill", "定位",
                         active: controller.locateState == .following) { controller.cycleLocate() }
                    Spacer()
                    ctrl("scope", "回到原点") { controller.fitTrack() }
                    if hasWaypoints {
                        ctrl("mappin.and.ellipse", "标记点", active: showWaypoints) { showWaypoints.toggle() }
                    }
                    ctrl("mountain.2", "等高线", active: showContours) { onContours() }
                    if hasProfile {
                        ctrl("chart.xyaxis.line", "剖面", active: showProfile) { onProfile() }
                    }
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
                Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColor.ink).frame(width: 36, height: 36)
            }
            Rectangle().fill(AppColor.divider).frame(width: 36, height: 1)
            Button { controller.zoomOut() } label: {
                Image(systemName: "minus").font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColor.ink).frame(width: 36, height: 36)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }

    /// 缩放滑块：与 MapScreen 不同，这里由地图当前 zoom 在 [minZoom,maxZoom] 的占比反推圆点位置。
    /// 加长滑轨；绿点滑块不放数字，拖动时数值在左侧白气泡显示（避免被手指遮挡）。
    private var zoomSlider: some View {
        let trackH: CGFloat = 220, thumb: CGFloat = 28
        // 把当前缩放级别归一化到 0…1；区间无效时取中点 0.5
        let frac = (controller.maxZoom - controller.minZoom) > 0
            ? (controller.zoom - controller.minZoom) / (controller.maxZoom - controller.minZoom) : 0.5
        let y = CGFloat(1 - min(1, max(0, frac))) * (trackH - thumb)
        return ZStack(alignment: .top) {
            Capsule().fill(Color.white.opacity(0.6)).frame(width: 4, height: trackH)
            if zoomDragging {
                Text(String(format: "%.1f", controller.zoom))
                    .font(.system(size: 14, weight: .bold)).foregroundColor(AppColor.ink)
                    .padding(.vertical, 5).padding(.horizontal, 10)
                    .background(Color.white).cornerRadius(9)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    .offset(x: -48, y: y + thumb / 2 - 14)
            }
            Circle().fill(AppColor.primary).frame(width: thumb, height: thumb)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                .offset(y: y)
        }
        .frame(width: thumb, height: trackH)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { v in
                    zoomDragging = true
                    controller.setZoom(fraction: 1 - Double(v.location.y) / trackH)
                }
                .onEnded { _ in zoomDragging = false }
        )
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
