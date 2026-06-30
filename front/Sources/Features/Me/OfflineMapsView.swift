import SwiftUI
import UniformTypeIdentifiers
import MapLibre

/// 离线地图管理（任务 2.7 / A 段）：导入 / 列表 / 删除 本地矢量离线包(.pmtiles)。
/// 离线包由电脑侧 planetiler 生成（见 tools/ 文档），导入后在地图页「图层」切到离线矢量底图。
struct OfflineMapsView: View {
    @State private var packs: [URL] = []                // 本地已导入的离线包文件（矢量/影像/等高线）
    @State private var regions: [MLNOfflinePack] = []   // 已缓存的离线影像区域
    @State private var showImporter = false             // 是否弹出系统文件选择器
    @State private var shareURL: URL?                   // 待分享/导出的离线包；非 nil 时弹分享面板
    @State private var importing = false                // 导入进行中（遮罩 loading）

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
                        // 左滑删除：移除该缓存区域，回调里刷新列表
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                MLNOfflineStorage.shared.removePack(pack) { _ in reloadRegions() }
                            } label: { Label("删除", systemImage: "trash") }
                            .tint(AppColor.recording)
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
                            .tint(AppColor.recording)
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
        // 选到文件后在后台线程导入；为避免遮罩一闪而过，导入太快时补足到至少 2 秒
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data]) { result in
            guard case .success(let url) = result else { return }
            importing = true
            Task.detached {
                let start = Date()
                _ = try? OfflineMaps.importPack(from: url)   // 显式丢弃结果（try? 包出的 URL? 不受 @discardableResult 覆盖）
                let elapsed = Date().timeIntervalSince(start)
                if elapsed < 2 { try? await Task.sleep(nanoseconds: UInt64((2 - elapsed) * 1_000_000_000)) }
                await MainActor.run { importing = false; reload() }   // 回主线程收起遮罩并刷新
            }
        }
        .overlay {
            if importing {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("导入中…").font(.subheadline).foregroundColor(AppColor.ink)
                    }
                    .padding(24).background(.regularMaterial).cornerRadius(14)
                }
            }
        }
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let shareURL { ShareSheet(items: [shareURL]) }
        }
    }

    /// 按文件类型给出中文标签（栅格影像/等高线/矢量底图），用于列表副标题。
    private func typeLabel(_ url: URL) -> String {
        if OfflineMaps.isRaster(url) { return "影像（栅格）" }
        if OfflineMaps.isContour(url) { return "等高线" }
        return "矢量底图"
    }
    /// 从缓存包的 context（下载时写入的名称）解码区域名，缺省回退「影像区域」。
    private func regionName(_ pack: MLNOfflinePack) -> String {
        String(data: pack.context, encoding: .utf8) ?? "影像区域"
    }
    /// 已下载字节换算为 MB，供列表展示。
    private func regionMB(_ pack: MLNOfflinePack) -> Double {
        Double(pack.progress.countOfTileBytesCompleted) / 1024 / 1024
    }
    /// 刷新已缓存影像区域列表（来自 MapLibre 离线存储）。
    private func reloadRegions() { regions = MLNOfflineStorage.shared.packs ?? [] }
    /// 整体刷新：重读本地离线包文件 + 缓存区域。
    private func reload() {
        packs = OfflineMaps.list()
        reloadRegions()
    }
}
