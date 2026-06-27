import SwiftUI
import UniformTypeIdentifiers

/// 外部打开文件的接收协调器（微信/系统“用本应用打开” → onOpenURL）。
final class ImportCoordinator: ObservableObject {
    static let shared = ImportCoordinator()
    @Published var pendingURL: URL?
}

/// 轨迹库（任务 6.2，参照图3）：全屏沉浸；本地/云端分段 + 搜索 + 文件夹分组 + 滑删/移动。
/// 外层 NavigationStack 由 RootTabView 提供（此处不再嵌套）。
struct TracksView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var segment = 0           // 顶部分段：0 本地 / 1 云端
    @State private var search = ""           // 搜索关键词，按名称大小写不敏感过滤
    @State private var tracks: [Track] = []   // 全部本地轨迹（含分组与未分组）
    @State private var folders: [Folder] = [] // 文件夹列表，每个对应一个可折叠分组
    @State private var expanded: Set<String> = ["ungrouped"]  // 展开的分组键集合；默认展开「未分组」
    @State private var showImport = false     // 是否弹出导入预览 sheet
    @State private var showCreateFolder = false  // 是否弹出新建文件夹 alert
    @State private var newFolderName = ""     // 新建文件夹名称输入框
    @State private var moveTarget: Track?     // 正在移动到文件夹的轨迹，非 nil 即弹选择面板

    private let repo = TrackRepository()      // 数据访问层：轨迹/文件夹的增删改查

    var body: some View {
        VStack(spacing: 0) {
            header
            if segment == 0 { localList } else { cloudPlaceholder }
            bottomBar
        }
        .navigationBarHidden(true)
        .navigationDestination(for: UUID.self) { TrackDetailView(trackId: $0) }
        .onAppear(perform: reload)
        .sheet(isPresented: $showImport, onDismiss: reload) {
            NavigationStack { ImportPreviewView() }
        }
        .alert("新建文件夹", isPresented: $showCreateFolder) {
            TextField("文件夹名称", text: $newFolderName)
            Button("创建") { createFolder() }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("移动到文件夹", isPresented: Binding(
            get: { moveTarget != nil }, set: { if !$0 { moveTarget = nil } }
        ), presenting: moveTarget) { t in
            ForEach(folders) { f in Button(f.name) { move(t, to: f.id) } }
            Button("未分组") { move(t, to: nil) }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - 顶部
    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AppColor.primary)
                    }
                    Spacer()
                }
                Picker("", selection: $segment) {
                    Text("本地").tag(0); Text("云端").tag(1)
                }.pickerStyle(.segmented).frame(width: 160)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(AppColor.ink2)
                TextField("请输入关键词", text: $search)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
            }
            .padding(.vertical, 8).padding(.horizontal, 10)
            .background(Color(hex: 0xF2F3F5)).cornerRadius(10)
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
    }

    // MARK: - 本地列表
    @ViewBuilder private var localList: some View {
        if tracks.isEmpty && folders.isEmpty {
            emptyState
        } else if shown.isEmpty && !search.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "magnifyingglass").font(.system(size: 36)).foregroundColor(AppColor.ink2)
                Text("没有匹配「\(search)」的轨迹").foregroundColor(AppColor.ink2)
                Spacer()
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(folders) { f in
                    groupSection(title: f.name, key: f.id.uuidString, items: tracksIn(f.id))
                }
                groupSection(title: "未分组", key: "ungrouped", items: ungrouped)
            }
            .listStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.system(size: 50)).foregroundColor(AppColor.divider)
            Text("还没有轨迹").font(.headline)
            Text("去「地图」开始记录，或从微信/文件导入轨迹").font(.subheadline)
                .foregroundColor(AppColor.ink2).multilineTextAlignment(.center)
            Button { showImport = true } label: {
                Text("导入轨迹").fontWeight(.semibold).foregroundColor(.white)
                    .padding(.horizontal, 24).frame(height: 44).background(AppColor.primary).cornerRadius(AppRadius.button)
            }
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }

    /// 一个可折叠分组：标题栏点击切换展开/收起；展开时列出轨迹，空分组显示「（空）」。
    /// - key: 分组唯一键（文件夹用 UUID 字符串，未分组用 "ungrouped"），用于记录展开状态。
    private func groupSection(title: String, key: String, items: [Track]) -> some View {
        Section {
            if expanded.contains(key) {
                if items.isEmpty {
                    Text("（空）").font(.caption).foregroundColor(AppColor.ink2)
                } else {
                    ForEach(items) { trackRow($0) }
                }
            }
        } header: {
            Button { toggle(key) } label: {
                HStack {
                    Image(systemName: expanded.contains(key) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("\(items.count) 条").font(.caption)
                }.foregroundColor(AppColor.ink)
            }
        }
    }

    private func trackRow(_ t: Track) -> some View {
        NavigationLink(value: t.id) {
            VStack(alignment: .leading, spacing: 4) {
                Text(t.name).font(.system(size: 15, weight: .semibold))
                Text(String(format: "%.2f km · ↑%.0f m · %@ · %@",
                            t.distance / 1000, t.ascent,
                            t.source == .recorded ? "记录" : "导入", Self.df.string(from: t.createdAt)))
                    .font(.caption).foregroundColor(AppColor.ink2)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { delete(t) } label: { Label("删除", systemImage: "trash") }
            Button { moveTarget = t } label: { Label("移动", systemImage: "folder") }.tint(AppColor.info)
        }
    }

    // MARK: - 云端占位
    private var cloudPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "cloud").font(.system(size: 44)).foregroundColor(AppColor.ink2)
            Text("登录后云端同步 · 三期").foregroundColor(AppColor.ink2)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 底部按钮
    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button { showImport = true } label: {
                Text("导入轨迹").fontWeight(.semibold).foregroundColor(AppColor.ink)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .overlay(RoundedRectangle(cornerRadius: AppRadius.button).stroke(AppColor.divider))
            }
            Button { newFolderName = ""; showCreateFolder = true } label: {
                Text("创建文件夹").fontWeight(.semibold).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(AppColor.primary).cornerRadius(AppRadius.button)
            }
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: - 数据/动作
    /// 经搜索过滤后的轨迹集合（关键词为空则返回全部）；下面分组都基于它再切分。
    private var shown: [Track] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? tracks : tracks.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }
    /// 未归入任何文件夹的轨迹。
    private var ungrouped: [Track] { shown.filter { $0.folderId == nil } }
    /// 指定文件夹下的轨迹。
    private func tracksIn(_ id: UUID) -> [Track] { shown.filter { $0.folderId == id } }

    /// 切换某分组的展开/收起状态。
    private func toggle(_ key: String) {
        if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
    }
    /// 重新从仓库加载轨迹与文件夹（出现/导入/增删后刷新）。
    private func reload() {
        tracks = (try? repo.listTracks()) ?? []
        folders = (try? repo.listFolders()) ?? []
    }
    /// 软删除轨迹并刷新。
    private func delete(_ t: Track) { try? repo.softDelete(id: t.id); reload() }
    /// 把轨迹移动到目标文件夹（nil 表示移出到未分组）。
    private func move(_ t: Track, to folderId: UUID?) {
        try? repo.moveTrack(id: t.id, to: folderId)
        if let fid = folderId { expanded.insert(fid.uuidString) }   // 展开目标文件夹，立刻可见
        reload()
    }
    /// 创建文件夹（名称去空白后为空则忽略），刷新列表。
    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        try? repo.createFolder(name: name); reload()
    }

    private static let df: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
}

/// 导入预览（任务 5.3/5.4）：文件来自外部打开或应用内选择 → 解析 → 预览 → 确认入库。
struct ImportPreviewView: View {
    let fileURL: URL?
    @Environment(\.dismiss) private var dismiss

    @State private var parsed: [GPXService.ParsedTrack] = []  // 解析出的待导入轨迹（可能多条）
    @State private var errorMsg: String?       // 解析/入库错误文案，非 nil 时显示错误态
    @State private var showPicker = false      // 是否弹出系统文件选择器
    @State private var imported = false        // 是否已成功入库，切到成功态

    init(fileURL: URL? = nil) { self.fileURL = fileURL }

    // 允许导入的文件类型：GPX / KML
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
    /// 解析所选文件为预览轨迹。外部 URL 需先取得安全作用域访问权限，结束后释放（defer）。
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

    /// 确认导入：逐条入库，全部成功切到成功态，任一失败显示错误。
    private func confirmImport() {
        do {
            for t in parsed { try ImportService.save(t) }
            imported = true
        } catch {
            errorMsg = "入库失败：\(error.localizedDescription)"
        }
    }
}
