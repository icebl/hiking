import SwiftUI

/// 沿轨迹导航（任务 4.7）：计划线 + 状态条 + 偏航横幅 + 剩余信息。
struct NavigationRunView: View {
    let trackId: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var offRoute = false       // 由 NavigationEngine 驱动（任务 4.3/4.4）
    @State private var reverse = false         // 方向选择（任务 4.5）
    @State private var alsoRecord = true       // 同时记录默认开

    var body: some View {
        ZStack {
            MapLibreView().ignoresSafeArea()

            if offRoute {
                VStack { Text("⚠ 已偏离计划线 27m，请返回")
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                    .padding(10).frame(maxWidth: .infinity).background(AppColor.warning).cornerRadius(12)
                    Spacer() }.padding(.horizontal, 12).padding(.top, 8)
            }

            VStack {
                Spacer()
                HStack {
                    Text("状态：在线").foregroundColor(.white)
                    Spacer()
                    Text("剩余 12.3km · ↑680m").foregroundColor(.white)
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16).padding(.vertical, 10).background(Color.black.opacity(0.72))

                HStack(spacing: 12) {
                    Button { /* 暂停 */ } label: { navBtn("暂停", filled: false) }
                    Button { dismiss() } label: { navBtn("结束导航", filled: true) }
                }.padding(16)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(reverse ? "导航中 · 反向" : "导航中 · 正向")
        // TODO(4.x): 进入前弹方向选择 + 同时记录开关；接 NavigationEngine 更新 offRoute/剩余
    }

    private func navBtn(_ t: String, filled: Bool) -> some View {
        Text(t).fontWeight(.semibold).foregroundColor(filled ? .white : AppColor.ink)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(filled ? AppColor.recording : Color.white).cornerRadius(14)
    }
}
