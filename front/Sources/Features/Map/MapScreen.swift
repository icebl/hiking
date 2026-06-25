import SwiftUI

/// 地图（全屏沉浸，任务 2.x）：底图 + 悬浮控件 + 居中信息条 + 底部记录/导航 + 点击取经纬度。
/// 控件布局对齐 UI/视觉稿/原型.html：
///   左列：返回 / 定位 / 居中
///   右列：图层 / 叠加 / 工具 / 缩放(+/-) / 缩放滑块 / 公里标
struct MapScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var mapCtrl = MapController()
    @State private var showRecording = false
    @State private var tapped: String? = nil   // 点击地图取经纬度读数（任务 2.8）
    @State private var zoomLevel: Double = 0.5  // 缩放滑块位置（0…1）

    var body: some View {
        ZStack {
            MapLibreView(controller: mapCtrl)
                .ignoresSafeArea()

            // 信息条：靠上居中（WGS84 浅绿高亮）+ 缩放级别读数（诊断）
            VStack(spacing: 6) {
                infoBar
                zoomReadout
                Spacer()
            }
            .padding(.top, 6)

            // 左列：返回（顶）/ 定位 / 居中（中下）
            HStack {
                VStack(spacing: 0) {
                    ctrl("chevron.left") { dismiss() }
                    Spacer()
                    VStack(spacing: 14) {
                        ctrl("location.fill", "定位", filled: true) { mapCtrl.recenterOnUser() }
                        ctrl("scope", "居中") { mapCtrl.center() }
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding(.leading, 14)
            .padding(.top, 6)
            .padding(.bottom, 120)

            // 右列：图层 / 叠加 / 工具（顶）— 缩放 +/- + 滑块（中）— 公里标（下）
            HStack {
                Spacer()
                VStack(spacing: 14) {
                    ctrl("square.3.stack.3d", "图层")        // TODO(2.6): 切底图/卫星
                    ctrl("square.on.square", "叠加")          // TODO: 多轨迹叠加面板
                    ctrl("wrench.and.screwdriver", "工具")    // 工具箱（P1）
                    Spacer()
                    zoomGroup                                  // 缩放 +/-（已接 mapCtrl）
                    zoomSlider                                 // 滑块缩放（已接 mapCtrl）
                    Spacer()
                    ctrl("ruler", "公里标")                    // TODO(2.3): 每 1KM 里程标
                }
            }
            .padding(.trailing, 14)
            .padding(.top, 6)
            .padding(.bottom, 120)

            // 点击经纬度读数（带关闭）
            if let tapped {
                VStack {
                    Spacer()
                    HStack {
                        Text("地图上的点 ")
                            .foregroundColor(.white)
                        + Text(tapped).foregroundColor(Color(hex: 0x7EE0A6)).bold()
                        + Text(" · 海拔 未知").foregroundColor(.white)
                        Spacer()
                        Button { self.tapped = nil } label: {
                            Image(systemName: "xmark").foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .font(.caption)
                    .padding(.vertical, 10).padding(.horizontal, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.72))
                }
                .padding(.bottom, 96)
            }

            // 底部 记录 / 导航
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    Button { showRecording = true } label: { cta("记录", "record.circle", .white, AppColor.ink) }
                    Button { /* TODO(4.5): 选轨迹进入导航 */ } label: { cta("导航", "location.north.line.fill", AppColor.primary, .white) }
                }.padding(.horizontal, 16).padding(.bottom, 30)
            }
        }
        .fullScreenCover(isPresented: $showRecording) { RecordingView() }
    }

    // MARK: - 子组件

    private var infoBar: some View {
        (Text("WGS84").foregroundColor(Color(hex: 0x7EE0A6)).fontWeight(.bold)
         + Text(" 41.6950°N 123.3443°E · 海拔39m").foregroundColor(.white))
            .font(.system(size: 11.5, weight: .medium))
            .padding(.vertical, 6).padding(.horizontal, 14)
            .background(Color.black.opacity(0.72)).cornerRadius(12)
    }

    /// 缩放级别读数（诊断：能看到当前在哪一级；后续可移除）
    private var zoomReadout: some View {
        Text(String(format: "缩放 z%.1f", mapCtrl.zoom))
            .font(.system(size: 11, weight: .medium)).foregroundColor(.white)
            .padding(.vertical, 3).padding(.horizontal, 10)
            .background(Color.black.opacity(0.6)).cornerRadius(10)
    }

    /// 缩放 +/- 竖排药丸
    private var zoomGroup: some View {
        VStack(spacing: 0) {
            Button { mapCtrl.zoomIn() } label: {
                Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppColor.ink).frame(width: 44, height: 44)
            }
            Rectangle().fill(AppColor.divider).frame(width: 44, height: 1)
            Button { mapCtrl.zoomOut() } label: {
                Image(systemName: "minus").font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppColor.ink).frame(width: 44, height: 44)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }

    /// 缩放滑块（上滑放大 / 下滑缩小，任务 2.3 接真实缩放）
    private var zoomSlider: some View {
        ZStack(alignment: .top) {
            Capsule().fill(Color.white.opacity(0.6)).frame(width: 4, height: 110)
            Circle().fill(AppColor.primary).frame(width: 24, height: 24)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                .offset(y: CGFloat(1 - zoomLevel) * 86)
        }
        .frame(width: 24, height: 110)
        .contentShape(Rectangle())
        .gesture(
            DragGesture().onChanged { v in
                let frac = 1 - Double(v.location.y) / 110
                zoomLevel = min(1, max(0, frac))
                mapCtrl.setZoom(fraction: zoomLevel)
            }
        )
    }

    /// 悬浮圆形控件（可带下方小标签），filled 用于实心图标
    private func ctrl(_ icon: String, _ label: String? = nil, filled: Bool = false,
                      action: @escaping () -> Void = {}) -> some View {
        VStack(spacing: 3) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: filled ? .semibold : .regular))
                    .foregroundColor(AppColor.ink)
                    .frame(width: 44, height: 44)
                    .background(Color.white).clipShape(Circle())
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            }
            if let label {
                Text(label).font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
            }
        }
    }

    private func cta(_ t: String, _ icon: String, _ bg: Color, _ fg: Color) -> some View {
        HStack { Image(systemName: icon); Text(t).fontWeight(.semibold) }
            .foregroundColor(fg).frame(maxWidth: .infinity).frame(height: 52).background(bg).cornerRadius(AppRadius.button)
    }
}
