import SwiftUI

/// 诊断日志查看页（真机续航实测）：展示采样日志，可刷新/清空/导出分享给开发者分析。
/// 日志由 DiagnosticsLog 在记录/导航期间按 60s 采样写入（需在设置开启「诊断日志」）。
struct DiagnosticsView: View {
    @State private var text = ""          // 当前日志内容
    @State private var showShare = false  // 导出分享面板

    var body: some View {
        ScrollView {
            if text.isEmpty {
                Text(AppSettings.diagnostics
                     ? "暂无日志。开始一次记录/导航后，每分钟采样电量与前后台状态。"
                     : "诊断日志未开启。请到 设置 打开「诊断日志」。")
                    .font(.caption).foregroundColor(AppColor.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding()
            } else {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))   // 等宽便于对齐时间/数值
                    .frame(maxWidth: .infinity, alignment: .leading).padding()
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("诊断日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { text = DiagnosticsLog.contents() } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    Button { showShare = true } label: { Label("导出", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) { DiagnosticsLog.clear(); text = "" } label: { Label("清空", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .onAppear { text = DiagnosticsLog.contents() }
        .sheet(isPresented: $showShare) { ShareSheet(items: [DiagnosticsLog.fileURL]) }
    }
}
