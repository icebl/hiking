import SwiftUI

/// 沿轨迹导航（任务 4.5/4.7）：进入前选方向 + 同时记录 → 计划线 + 状态条 + 偏航横幅 + 长按结束。
struct NavigationRunView: View {
    let trackId: UUID
    @Environment(\.dismiss) private var dismiss
    @StateObject private var ctrl = NavigationController()
    @State private var started = false
    @State private var reverse = false
    @State private var alsoRecord = AppSettings.recordWhileNav   // 导航同时记录实走（默认取设置）
    @State private var showSaveDialog = false

    var body: some View {
        ZStack {
            MapLibreView(trackCoordinates: ctrl.planCoordinates, showsUserLocation: true, fitToTrack: true)
                .ignoresSafeArea()

            if !started { directionChooser } else { navigatingOverlay }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(started ? (reverse ? "导航中 · 反向" : "导航中 · 正向") : "开始导航")
        .onDisappear { ctrl.stop() }
        .confirmationDialog("保存本次轨迹？", isPresented: $showSaveDialog, titleVisibility: .visible) {
            Button("保存") { ctrl.finishSaving(); dismiss() }
            Button("不保存", role: .destructive) { ctrl.finishDiscarding(); dismiss() }
            Button("继续导航", role: .cancel) {}
        } message: { Text("导航时已同时记录你的实走轨迹。") }
    }

    // 进入前：方向选择 + 同时记录（任务 4.5）
    private var directionChooser: some View {
        VStack {
            Spacer()
            VStack(spacing: 16) {
                Text("选择导航方向").font(.headline)
                Picker("", selection: $reverse) { Text("正向").tag(false); Text("反向").tag(true) }
                    .pickerStyle(.segmented)
                Toggle("同时记录实走轨迹", isOn: $alsoRecord).tint(AppColor.primary)
                Button {
                    ctrl.start(trackId: trackId, reverse: reverse, alsoRecord: alsoRecord); started = true
                } label: {
                    Text("开始导航").fontWeight(.semibold).foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(AppColor.primary).cornerRadius(AppRadius.button)
                }
            }
            .padding(18).background(Color.white).cornerRadius(20)
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4).padding(16)
        }
    }

    // 导航中：横幅 + 状态条 + 长按结束
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

            // 结束：长按 3 秒（单击无效）
            Text("长按 3 秒结束导航").fontWeight(.semibold).foregroundColor(.white)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(AppColor.recording).cornerRadius(14)
                .padding(16)
                .onLongPressGesture(minimumDuration: 3) { endNavigation() }
        }
    }

    private func endNavigation() {
        if ctrl.isRecording { showSaveDialog = true }   // 弹保存询问（保存/不保存里 dismiss）
        else { ctrl.stop(); dismiss() }
    }

    private func banner(_ text: String, _ bg: Color) -> some View {
        Text(text).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
            .padding(10).frame(maxWidth: .infinity).background(bg).cornerRadius(12)
            .padding(.horizontal, 12).padding(.top, 8)
    }
}
