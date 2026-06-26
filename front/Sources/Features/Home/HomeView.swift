import SwiftUI

/// 首页（任务 6.1）：累计数据卡 + 快捷入口 + 活动·公告区（联网，P1）。
struct HomeView: View {
    var openMap: () -> Void
    @State private var summary: (count: Int, distance: Double, ascent: Double) = (0, 0, 0)
    @State private var showRecording = false
    @State private var showOffline = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("本月").font(.caption).foregroundColor(AppColor.ink2)
                    HStack {
                        stat("\(summary.count)", "轨迹")
                        Spacer(); stat(String(format: "%.1f", summary.distance / 1000), "里程 km")
                        Spacer(); stat("\(Int(summary.ascent))", "爬升 m")
                    }
                    .padding().background(Color.white).cornerRadius(AppRadius.card)

                    Text("快捷").font(.caption).foregroundColor(AppColor.ink2)
                    HStack(spacing: 12) {
                        Button { showRecording = true } label: {
                            quick("开始记录", "record.circle", AppColor.primary, .white)
                        }
                        Button { showOffline = true } label: {
                            quick("离线地图", "square.3.stack.3d", AppColor.primaryTint, AppColor.primaryDark)
                        }
                    }

                    Text("活动 · 公告").font(.caption).foregroundColor(AppColor.ink2)
                    // TODO(P1): 联网拉取运营发布的活动/公告，无网隐藏或显示缓存
                    VStack(alignment: .leading, spacing: 6) {
                        Text("周末徒步活动报名中").font(.headline).foregroundColor(.white)
                        Text("五台山经典环线 · 本周六出发").font(.caption).foregroundColor(.white.opacity(0.9))
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [AppColor.primary, AppColor.contour], startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(AppRadius.card)
                }
                .padding()
            }
            .background(Color(hex: 0xF2F3F5))
            .navigationTitle("路迹")
            .navigationDestination(isPresented: $showOffline) { OfflineMapsView() }
            .fullScreenCover(isPresented: $showRecording) { RecordingView() }
            .task { summary = (try? TrackRepository().monthlySummary()) ?? (0, 0, 0) }
        }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack { Text(v).font(.dataMid()).foregroundColor(AppColor.ink); Text(l).font(.caption).foregroundColor(AppColor.ink2) }
    }
    private func quick(_ t: String, _ icon: String, _ bg: Color, _ fg: Color) -> some View {
        HStack { Image(systemName: icon); Text(t).fontWeight(.semibold) }
            .foregroundColor(fg).frame(maxWidth: .infinity).frame(height: 64).background(bg).cornerRadius(AppRadius.card)
    }
}
