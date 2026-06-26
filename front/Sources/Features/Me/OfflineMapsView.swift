import SwiftUI
import UniformTypeIdentifiers
import MapLibre

/// 离线地图管理（任务 2.7 / A 段）：导入 / 列表 / 删除 本地矢量离线包(.pmtiles)。
/// 离线包由电脑侧 planetiler 生成（见 tools/ 文档），导入后在地图页「图层」切到离线矢量底图。
struct OfflineMapsView: View {
    @State private var packs: [URL] = []
    @State private var regions: [MLNOfflinePack] = []   // 已缓存的离线影像区域
    @State private var showImporter = false
    @State private var shareURL: URL?

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

            Section("离线影像区域（已缓存）") {
                if regions.isEmpty {
                    Text("暂无（用上方「框选下载」）").foregroundColor(AppColor.ink2)
                } else {
                    ForEach(regions, id: \.self) { pack in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(regionName(pack)).font(.system(size: 15, weight: .semibold))
                            Text(String(format: "影像缓存 · %.1f MB", regionMB(pack)))
                                .font(.caption).foregroundColor(AppColor.ink2)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                MLNOfflineStorage.shared.removePack(pack) { _ in reloadRegions() }
                            } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                }
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
                        .swipeActions(edge: .leading) {
                            Button { shareURL = url } label: { Label("导出", systemImage: "square.and.arrow.up") }
                                .tint(AppColor.info)
                        }
                        .contextMenu {
                            Button { shareURL = url } label: { Label("导出 / 分享", systemImage: "square.and.arrow.up") }
                        }
                    }
                }
            }
        }
        .navigationTitle("离线地图")
        .onAppear {
            reload()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { reloadRegions() }  // packs 异步加载兜底
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data]) { result in
            if case .success(let url) = result {
                try? OfflineMaps.importPack(from: url)
                reload()
            }
        }
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let shareURL { ShareSheet(items: [shareURL]) }
        }
    }

    private func typeLabel(_ url: URL) -> String {
        if OfflineMaps.isRaster(url) { return "影像（栅格）" }
        if OfflineMaps.isContour(url) { return "等高线" }
        return "矢量底图"
    }
    private func regionName(_ pack: MLNOfflinePack) -> String {
        String(data: pack.context, encoding: .utf8) ?? "影像区域"
    }
    private func regionMB(_ pack: MLNOfflinePack) -> Double {
        Double(pack.progress.countOfTileBytesCompleted) / 1024 / 1024
    }
    private func reloadRegions() { regions = MLNOfflineStorage.shared.packs ?? [] }
    private func reload() {
        packs = OfflineMaps.list()
        reloadRegions()
    }
}
