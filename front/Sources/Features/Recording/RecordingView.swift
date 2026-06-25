import SwiftUI

/// 记录中（任务 3.11）：地图 + 实时数据面板 + 暂停/结束。
struct RecordingView: View {
    var resumeSessionId: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var ctrl = RecordingController()

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

                HStack(spacing: 12) {
                    Button { ctrl.state == .paused ? ctrl.resume() : ctrl.pause() } label: {
                        label(ctrl.state == .paused ? "继续" : "暂停", filled: false)
                    }
                    Button {
                        _ = try? ctrl.finish(); dismiss()
                    } label: { label("结束", filled: true) }
                }
            }
            .padding().background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22))
        }
        .ignoresSafeArea(edges: .top)
        .onAppear { if let resumeSessionId { ctrl.resume(sessionId: resumeSessionId) } else { ctrl.start() } }
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
