import SwiftUI
import UIKit

/// 记录中（任务 3.11）：地图 + 实时数据面板 + 暂停/结束。
struct RecordingView: View {
    var resumeSessionId: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var ctrl = RecordingController()
    @State private var showPermAlert = false
    @State private var showMarkDialog = false
    @State private var markToast: String?

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                MapLibreView(trackCoordinates: ctrl.liveCoordinates, showsUserLocation: true)
                    .frame(maxHeight: .infinity)
                HStack(spacing: 8) {
                    Circle().fill(ctrl.isAutoPaused ? AppColor.ink2 : AppColor.recording).frame(width: 9, height: 9)
                    Text(ctrl.isAutoPaused ? "自动暂停中 · 静止" : "记录中 · GPS良好")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                }
                .padding(.vertical, 7).padding(.horizontal, 14)
                .background(Color.black.opacity(0.72)).cornerRadius(18).padding(.top, 8)

                if let markToast {
                    Text(markToast)
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                        .padding(.vertical, 8).padding(.horizontal, 16)
                        .background(Color.black.opacity(0.8)).cornerRadius(14)
                        .padding(.top, 56)
                        .transition(.opacity)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.2f", ctrl.distance / 1000)).font(.dataBig())
                    Text("km").font(.system(size: 15, weight: .semibold)).foregroundColor(AppColor.ink2)
                }
                Text("累计距离").font(.caption).foregroundColor(AppColor.ink2)

                HStack {
                    metric("\(Int(ctrl.ascent))", "累计爬升 m", AppColor.primary)
                    Spacer(); metric("\(Int(ctrl.descent))", "累计下降 m", AppColor.ink2)
                    Spacer(); metric(timeString(ctrl.movingTime), "用时", AppColor.ink)
                    Spacer(); metric("\(ctrl.pointCount)", "轨迹点", AppColor.ink)
                }

                Button { showMarkDialog = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                        Text(ctrl.waypointCount > 0 ? "打点 · 已标 \(ctrl.waypointCount)" : "打点")
                    }
                    .fontWeight(.semibold).foregroundColor(AppColor.info)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .overlay(RoundedRectangle(cornerRadius: AppRadius.button).stroke(AppColor.info.opacity(0.5)))
                }

                HStack(spacing: 12) {
                    Button { ctrl.state == .paused ? ctrl.resume() : ctrl.pause() } label: {
                        label(ctrl.state == .paused ? "继续" : "暂停", filled: false)
                    }
                    HoldToEndButton(title: "长按 3 秒结束") { _ = try? ctrl.finish(); dismiss() }
                }
            }
            .padding().background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22))
        }
        .ignoresSafeArea(edges: .top)
        .onAppear { startFlow() }
        .confirmationDialog("标注点类型", isPresented: $showMarkDialog, titleVisibility: .visible) {
            ForEach(WaypointKind.allOrdered, id: \.self) { k in
                Button(k.label) { mark(k) }
            }
            Button("取消", role: .cancel) {}
        } message: { Text("在当前位置打一个标注点") }
        .alert("需要定位权限", isPresented: $showPermAlert) {
            Button("去设置") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
            Button("取消", role: .cancel) { dismiss() }
        } message: {
            Text("记录轨迹需要定位权限。请在 设置 → 路迹 → 位置 中允许（建议「始终」以便锁屏后台记录）。")
        }
    }

    private func startFlow() {
        let loc = LocationManager.shared
        if loc.denied { showPermAlert = true; return }
        loc.requestWhenInUse()   // 未决定→系统弹窗；已授权→无副作用
        if let resumeSessionId { ctrl.resume(sessionId: resumeSessionId) } else { ctrl.start() }
    }

    /// 打点：在当前位置落标注点，给一次轻提示。
    private func mark(_ kind: WaypointKind) {
        let ok = ctrl.addWaypoint(kind: kind)
        let msg = ok ? "已标注：\(kind.label)" : "定位未就绪，稍后再试"
        withAnimation { markToast = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { if markToast == msg { markToast = nil } }
        }
    }

    private func timeString(_ s: TimeInterval) -> String {
        let t = Int(s); return String(format: "%02d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }

    private func metric(_ v: String, _ l: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.dataMid()).foregroundColor(c).lineLimit(1).minimumScaleFactor(0.6)
            Text(l).font(.caption).foregroundColor(AppColor.ink2).lineLimit(1)
        }
    }
    private func label(_ t: String, filled: Bool) -> some View {
        Text(t).fontWeight(.semibold).foregroundColor(filled ? .white : AppColor.ink)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(filled ? AppColor.recording : Color.white)
            .overlay(RoundedRectangle(cornerRadius: AppRadius.button).stroke(filled ? .clear : AppColor.divider))
            .cornerRadius(AppRadius.button)
    }
}
