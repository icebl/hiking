import SwiftUI
import UniformTypeIdentifiers

/// 外部打开文件的接收协调器（微信/系统“用本应用打开” → onOpenURL）。
final class ImportCoordinator: ObservableObject {
    static let shared = ImportCoordinator()
    @Published var pendingURL: URL?
}

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
            .onAppear { reload() }   // 返回即刷新（含导入后）
        }
    }

    private func reload() { tracks = (try? TrackRepository().listTracks()) ?? [] }
}

/// 导入预览（任务 5.3/5.4）：文件来自外部打开或应用内选择 → 解析 → 预览 → 确认入库。
struct ImportPreviewView: View {
    let fileURL: URL?
    @Environment(\.dismiss) private var dismiss

    @State private var parsed: [GPXService.ParsedTrack] = []
    @State private var errorMsg: String?
    @State private var showPicker = false
    @State private var imported = false

    init(fileURL: URL? = nil) { self.fileURL = fileURL }

    private static let importTypes: [UTType] =
        ["gpx", "kml"].compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        Group {
            if imported {
                statusView(icon: "checkmark.circle.fill", color: AppColor.primary, text: "已导入到“轨迹”")
            } else if let errorMsg {
                statusView(icon: "exclamationmark.triangle.fill", color: AppColor.warning, text: errorMsg)
            } else if parsed.isEmpty {
                emptyPicker
            } else {
                preview
            }
        }
        .navigationTitle("导入轨迹")
        .toolbar { ToolbarItem(placement: .topBarLeading) {
            Button("关闭") { dismiss() }
        } }
        .onAppear { if let fileURL, parsed.isEmpty, errorMsg == nil { load(fileURL) } }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: Self.importTypes) { result in
            if case .success(let url) = result { load(url) }
        }
    }

    // MARK: - 子视图
    private var emptyPicker: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.and.arrow.down").font(.system(size: 40)).foregroundColor(AppColor.ink2)
            Text("从文件选择 GPX / KML 轨迹导入").font(.subheadline).foregroundColor(AppColor.ink2)
            Button { showPicker = true } label: {
                Text("选择文件").fontWeight(.semibold).foregroundColor(.white)
                    .frame(maxWidth: 200).frame(height: 48).background(AppColor.primary).cornerRadius(AppRadius.button)
            }
        }.padding()
    }

    private var preview: some View {
        List {
            ForEach(parsed.indices, id: \.self) { i in
                let t = parsed[i]
                let s = ImportService.statistics(of: t.points)
                VStack(alignment: .leading, spacing: 6) {
                    Text(t.name).font(.system(size: 16, weight: .bold))
                    Text(String(format: "距离 %.2f km · 爬升 %.0f m · 点 %d · 航点 %d",
                                s.distance / 1000, s.ascent, t.points.count, t.waypoints.count))
                        .font(.caption).foregroundColor(AppColor.ink2)
                    if !t.hasTime {
                        Label("该文件缺少时间戳", systemImage: "clock.badge.exclamationmark")
                            .font(.caption2).foregroundColor(AppColor.warning)
                    }
                }.padding(.vertical, 4)
            }
            Section {
                Button { confirmImport() } label: {
                    Text("确认导入（\(parsed.count) 条）").fontWeight(.semibold)
                        .frame(maxWidth: .infinity).foregroundColor(.white)
                }
                .listRowBackground(AppColor.primary)
            }
        }
    }

    private func statusView(icon: String, color: Color, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 44)).foregroundColor(color)
            Text(text).font(.subheadline).multilineTextAlignment(.center).foregroundColor(AppColor.ink)
            Button("完成") { dismiss() }.padding(.top, 4)
        }.padding()
    }

    // MARK: - 逻辑
    private func load(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            parsed = try ImportService.parse(url: url)
            errorMsg = parsed.isEmpty ? "文件中未找到可导入的轨迹" : nil
        } catch {
            errorMsg = (error as? LocalizedError)?.errorDescription ?? "解析失败：\(error.localizedDescription)"
        }
    }

    private func confirmImport() {
        do {
            for t in parsed { try ImportService.save(t) }
            imported = true
        } catch {
            errorMsg = "入库失败：\(error.localizedDescription)"
        }
    }
}
