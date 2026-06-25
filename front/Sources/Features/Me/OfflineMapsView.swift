import SwiftUI
import UniformTypeIdentifiers

/// 离线地图管理（任务 2.7 / A 段）：导入 / 列表 / 删除 本地矢量离线包(.pmtiles)。
/// 离线包由电脑侧 planetiler 生成（见 tools/ 文档），导入后在地图页「图层」切到离线矢量底图。
struct OfflineMapsView: View {
    @State private var packs: [URL] = []
    @State private var showImporter = false

    var body: some View {
        List {
            Section("已导入离线包（矢量底图）") {
                if packs.isEmpty {
                    Text("暂无离线包").foregroundColor(AppColor.ink2)
                } else {
                    ForEach(packs, id: \.self) { url in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(url.deletingPathExtension().lastPathComponent)
                                .font(.system(size: 15, weight: .semibold))
                            Text(String(format: "%.1f MB", OfflineMaps.sizeMB(url)))
                                .font(.caption).foregroundColor(AppColor.ink2)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { OfflineMaps.delete(url); reload() } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            Section {
                Button { showImporter = true } label: {
                    Label("导入 .pmtiles", systemImage: "square.and.arrow.down")
                }
            } footer: {
                Text("用电脑侧 planetiler 生成区域 .pmtiles（见 tools/ 文档），通过 AirDrop / 文件 App 导入；"
                     + "随后在地图页右上「图层」切换为离线矢量底图，断网可用。")
            }
        }
        .navigationTitle("离线地图")
        .onAppear(perform: reload)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data]) { result in
            if case .success(let url) = result {
                try? OfflineMaps.importPack(from: url)
                reload()
            }
        }
    }

    private func reload() { packs = OfflineMaps.list() }
}
