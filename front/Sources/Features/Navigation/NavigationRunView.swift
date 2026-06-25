import SwiftUI

/// 沿轨迹导航（任务 4.5/4.7）：进入前选方向 → 计划线 + 状态条 + 偏航横幅 + 剩余信息。
struct NavigationRunView: View {
    let trackId: UUID
    @Environment(\.dismiss) private var dismiss
    @StateObject private var ctrl = NavigationController()
    @State private var started = false
    @State private var reverse = false

    var body: some View {
        ZStack {
            MapLibreView(trackCoordinates: ctrl.planCoordinates, showsUserLocation: true, fitToTrack: true)
                .ignoresSafeArea()

            if !started {
                directionChooser
            } else {
                navigatingOverlay
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(started ? (reverse ? "导航中 · 反向" : "导航中 · 正向") : "开始导航")
        .onDisappear { ctrl.stop() }
    }

    // 进入前：方向选择（任务 4.5）
    private var directionChooser: some View {
        VStack {
            Spacer()
            VStack(spacing: 16) {
                Text("选择导航方向").font(.headline)
                Picker("", selection: $reverse) {
                    Text("正向").tag(false); Text("反向").tag(true)
                }.pickerStyle(.segmented)
                Button {
                    ctrl.start(trackId: trackId, reverse: reverse); started = true
                } label: {
                    Text("开始导航").fontWeight(.semibold).foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(AppColor.primary).cornerRadius(AppRadius.button)
                }
            }
            .padding(18)
            .background(Color.white).cornerRadius(20)
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .padding(16)
        }
    }

    // 导航中：横幅 + 状态条
    private var navigatingOverlay: some View {
        VStack {
            if ctrl.isOffRoute {
                banner("⚠ 已偏离计划线 \(Int(ctrl.distanceToLine))m，请返回", AppColor.warning)
            } else if ctrl.arrived {
                banner("🏁 已到达终点附近", AppColor.primary)
            }
            Spacer()

            HStack {
                Text(ctrl.isOffRoute ? "状态：偏航" : "状态：在线").foregroundColor(.white)
                Spacer()
                Text(String(format: "剩余 %.2fkm · ↑%dm", ctrl.remainingDistance / 1000, Int(ctrl.remainingAscent)))
                    .foregroundColor(.white)
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 10).background(Color.black.opacity(0.72))

            HStack(spacing: 12) {
                Button { ctrl.stop(); dismiss() } label: { navBtn("结束导航", filled: true) }
            }.padding(16)
        }
    }

    private func banner(_ text: String, _ bg: Color) -> some View {
        Text(text).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
            .padding(10).frame(maxWidth: .infinity).background(bg).cornerRadius(12)
            .padding(.horizontal, 12).padding(.top, 8)
    }

    private func navBtn(_ t: String, filled: Bool) -> some View {
        Text(t).fontWeight(.semibold).foregroundColor(filled ? .white : AppColor.ink)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(filled ? AppColor.recording : Color.white).cornerRadius(14)
    }
}
