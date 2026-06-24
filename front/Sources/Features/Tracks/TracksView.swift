import SwiftUI

/// 轨迹库（任务 6.2）：本地轨迹列表 → 详情。
struct TracksView: View {
    @State private var tracks: [Track] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(tracks) { t in
                    NavigationLink(value: t.id) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t.name).font(.system(size: 15, weight: .semibold))
                            Text(String(format: "%.2f km · ↑%.0f m · %@",
                                        t.distance / 1000, t.ascent, t.source == .recorded ? "记录" : "导入"))
                                .font(.caption).foregroundColor(AppColor.ink2)
                        }
                    }
                }
            }
            .navigationTitle("轨迹")
            .navigationDestination(for: UUID.self) { TrackDetailView(trackId: $0) }
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { ImportPreviewView() } label: { Image(systemName: "square.and.arrow.down") }
            } }
            .task { tracks = (try? TrackRepository().listTracks()) ?? [] }
        }
    }
}

/// 导入预览（任务 5.4，占位）。
struct ImportPreviewView: View {
    var body: some View {
        VStack { Text("导入预览").font(.headline); Text("// TODO(5.3/5.4): 文件选择 → 解析 → 预览 → 确认入库").font(.caption).foregroundColor(AppColor.ink2) }
            .navigationTitle("导入轨迹")
    }
}
