import SwiftUI
import UniformTypeIdentifiers

/// 离线地图管理（任务 2.7 / A 段）：导入 / 列表 / 删除 本地矢量离线包(.pmtiles)。
/// 离线包由电脑侧 planetiler 生成（见 tools/ 文档），导入后在地图页「图层」切到离线矢量底图。
struct OfflineMapsView: View {
    @State private var packs: [URL] = []
    @State private var showImporter = false

    var body: some View {
        List {
            Section {
                NavigationLink { OfflineDownloadView() } label: {
                    Label("下载离线影像（框选区域）", systemImage: "square.dashed.inset.filled")
                }
                Button { showImporter = true } label: {
                    Label("导入离线包（.pmtiles / .mbtiles）", systemImage: "square.and.arrow.down")
                }
            } footer: {
                Text("矢量底图用电脑侧 planetiler 生成 .pmtiles 后导入；卫星影像可直接「框选下载」。"
                     + "导入/下载后在地图页右上「图层」切换，断网可用。")
            }

            Section("已有离线包") {
                if packs.isEmpty {
                    Text("暂无离线包").foregroundColor(AppColor.ink2)
                } else {
                    ForEach(packs, id: \.self) { url in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(url.deletingPathExtension().lastPathComponent)
                                    .font(.system(size: 15, weight: .semibold))
                                Text(String(format: "%@ · %.1f MB", typeLabel(url), OfflineMaps.sizeMB(url)))
                                    .font(.caption).foregroundColor(AppColor.ink2)
                            }
                            Spacer()
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { OfflineMaps.delete(url); reload() } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
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

    private func typeLabel(_ url: URL) -> String {
        if OfflineMaps.isRaster(url) { return "影像（栅格）" }
        if OfflineMaps.isContour(url) { return "等高线" }
        return "矢量底图"
    }
    private func reload() { packs = OfflineMaps.list() }
}
