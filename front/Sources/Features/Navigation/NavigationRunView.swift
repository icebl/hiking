import SwiftUI
import UIKit

/// 沿轨迹导航（任务 4.5/4.7）：进入前选方向 + 同时记录 → 计划线 + 状态条 + 偏航横幅 + 长按结束。
struct NavigationRunView: View {
    let trackId: UUID                              // 要导航的计划轨迹 id
    @Environment(\.dismiss) private var dismiss
    @StateObject private var ctrl = NavigationController()  // 导航控制器，视图随其 @Published 刷新
    @State private var started = false             // false 显示方向选择，true 显示导航中界面
    @State private var reverse = false             // 用户所选方向：false 正向 / true 反向
    @State private var alsoRecord = AppSettings.recordWhileNav   // 导航同时记录实走（默认取设置）
    @State private var showSaveDialog = false      // 结束时若在记录，弹保存/不保存询问
    @State private var showPermAlert = false       // 定位被拒提示弹窗

    var body: some View {
        ZStack {
            MapLibreView(trackCoordinates: ctrl.planCoordinates, showsUserLocation: true, fitToTrack: true,
                         waypoints: ctrl.waypoints)
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
        .alert("需要定位权限", isPresented: $showPermAlert) {
            Button("去设置") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("沿轨迹导航需要定位权限来判断偏航。请在 设置 → 路迹 → 位置 中允许。")
        }
    }

    /// 确认权限后按所选方向/记录开关启动导航，切到导航中界面。
    private func beginNavigation() {
        let loc = LocationManager.shared
        if loc.denied { showPermAlert = true; return }
        loc.requestWhenInUse()
        ctrl.start(trackId: trackId, reverse: reverse, alsoRecord: alsoRecord)
        started = true
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
                    beginNavigation()
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
            } else if let w = ctrl.nearbyWaypoint {
                banner("📍 前方 \(Int(ctrl.nearbyWaypointDistance))m · \(w.kind.label) \(w.name)", w.kind.color)
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

            // 结束：长按 3 秒（防误触，进度填充）
            HoldToEndButton(title: "长按 3 秒结束导航") { endNavigation() }
                .padding(16)
        }
    }

    /// 结束导航：若在同时记录则弹保存询问（由弹窗按钮收尾并 dismiss），否则直接停并退出。
    private func endNavigation() {
        if ctrl.isRecording { showSaveDialog = true }   // 弹保存询问（保存/不保存里 dismiss）
        else { ctrl.stop(); dismiss() }
    }

    /// 顶部横幅小部件：文案 text + 背景色 bg（偏航/到达/航点接近共用）。
    private func banner(_ text: String, _ bg: Color) -> some View {
        Text(text).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
            .padding(10).frame(maxWidth: .infinity).background(bg).cornerRadius(12)
            .padding(.horizontal, 12).padding(.top, 8)
    }
}
