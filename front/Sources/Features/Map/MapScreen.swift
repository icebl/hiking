import SwiftUI

/// 地图（全屏沉浸，任务 2.x）：底图 + 悬浮控件 + 居中信息条 + 底部记录/导航 + 点击取经纬度。
struct MapScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showRecording = false
    @State private var tapped: String? = nil   // 点击地图取经纬度读数（任务 2.8）

    var body: some View {
        ZStack {
            MapLibreView()
                .ignoresSafeArea()
                .onTapGesture { /* TODO(2.8): 命中地图取坐标，按设置格式显示 */ tapped = "41.70123°N, 123.45130°E" }

            // 信息条：靠上居中
            VStack {
                Text("WGS84 41.6950°N 123.3443°E · 海拔39m · 定位误差22m")
                    .font(.system(size: 11.5, weight: .medium)).foregroundColor(.white)
                    .padding(.vertical, 6).padding(.horizontal, 14)
                    .background(Color.black.opacity(0.72)).cornerRadius(12)
                Spacer()
            }
            .padding(.top, 8)

            // 右侧控件（图层/叠加/工具/缩放/公里标）— TODO(2.3) 接真实交互
            VStack(spacing: 12) {
                control("square.3.stack.3d")   // 图层
                control("square.2.layers.3d")  // 叠加
                control("wrench.and.screwdriver") // 工具箱（P1）
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding([.top, .trailing], 14).padding(.top, 40)

            // 左上返回
            VStack { HStack { control("chevron.left") { dismiss() }; Spacer() }; Spacer() }
                .padding([.top, .leading], 14).padding(.top, 40)

            // 点击经纬度读数
            if let tapped {
                VStack { Spacer(); Text("地图上的点 \(tapped) · 海拔 未知")
                    .font(.caption).foregroundColor(.white).padding(10)
                    .frame(maxWidth: .infinity).background(Color.black.opacity(0.72)) }
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

    private func control(_ icon: String, _ action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            Image(systemName: icon).foregroundColor(AppColor.ink)
                .frame(width: 44, height: 44).background(Color.white).clipShape(Circle())
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        }
    }
    private func cta(_ t: String, _ icon: String, _ bg: Color, _ fg: Color) -> some View {
        HStack { Image(systemName: icon); Text(t).fontWeight(.semibold) }
            .foregroundColor(fg).frame(maxWidth: .infinity).frame(height: 52).background(bg).cornerRadius(AppRadius.button)
    }
}
