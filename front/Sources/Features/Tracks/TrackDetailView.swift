import SwiftUI
import CoreLocation

/// 轨迹详情（任务 6.2 / 5.6）：地图 / 详情 页签 + 操作（导出/导航）。
struct TrackDetailView: View {
    let trackId: UUID                                // 入参：要展示的轨迹 ID（其余数据 .task 时从仓库按需加载）
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0       // 顶部分段页签：0 地图 / 1 详情 / 2 标注点
    @State private var track: Track?                 // 轨迹元数据（名称、距离、爬升等），加载前为 nil
    @State private var points: [TrackPoint] = []     // 轨迹原始点序列（经纬度+海拔），用于建剖面/导出
    @State private var waypoints: [Waypoint] = []    // 航点（标注点）列表
    @State private var coords: [CLLocationCoordinate2D] = []  // points 投影出的坐标，供地图画线
    @State private var exportURL: URL?               // 导出生成的 GPX/KML 临时文件地址
    @State private var showShare = false             // 是否弹出系统分享面板
    @State private var showExportDialog = false      // 是否弹出导出格式选择（GPX/KML）
    @State private var exportError: String?          // 导出失败的错误文案，非 nil 即弹错误 alert
    @StateObject private var mapCtrl = MapController()  // 地图控制器：缩放/定位等命令出口
    @State private var showKm = false                // 是否显示每公里里程标
    @State private var showContours = false          // 是否叠加等高线图层
    @State private var showRoadNetwork = false       // 是否高亮路网图层（仅离线矢量底图可用）
    @State private var toast: String?                // 轻提示文案，非 nil 时浮层显示，1.5s 后自动清空
    @State private var baseMode: MapBaseMode = .onlineRaster  // 当前底图：在线影像 / 离线矢量
    @State private var showLayerSheet = false        // 是否弹出底图选择面板
    @State private var profile: [ElevSample] = []    // 海拔剖面采样（.task 中 buildProfile 生成）
    @State private var selectedProfileIndex: Int?    // 剖面被拖选的采样下标 → 地图高亮该点；nil 为未选
    @State private var showProfile = false           // 默认不展开海拔剖面
    @State private var showWaypoints = true          // 轨迹上标记点显隐
    @State private var showRename = false            // 是否弹出重命名 alert
    @State private var renameText = ""               // 重命名输入框绑定值
    @State private var showDeleteConfirm = false     // 是否弹出删除确认
    // 标注点（航点）管理
    @State private var focusWaypoint: Waypoint?         // 列表点击 → 地图居中目标
    @State private var editingWaypoint: Waypoint?       // 正在编辑名称/备注的航点
    @State private var editWpName = ""                  // 编辑航点名称输入框
    @State private var editWpNote = ""                  // 编辑航点备注输入框
    @State private var showEditWaypoint = false         // 是否弹出编辑航点 alert
    @State private var kindPickWaypoint: Waypoint?      // 正在更改类型的航点
    @State private var showKindDialog = false           // 是否弹出类型选择面板

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) { Text("地图").tag(0); Text("详情").tag(1); Text("标注点").tag(2) }
                .pickerStyle(.segmented).padding()

            if tab == 0 {
                mapTab
            } else if tab == 1 {
                statsList
            } else {
                waypointList
            }

            // 标记点页隐藏底部按钮；地图页展开剖面时也隐藏（给剖面让空间）。
            if tab != 2 && !(tab == 0 && showProfile && !profile.isEmpty) {
                HStack(spacing: 12) {
                    Button { showExportDialog = true } label: {
                        Text("导出").frame(maxWidth: .infinity).frame(height: 52)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColor.divider))
                    }
                    NavigationLink { NavigationRunView(trackId: trackId) } label: {
                        Text("使用轨迹导航").fontWeight(.semibold).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 52).background(AppColor.primary).cornerRadius(14)
                    }
                }.padding()
            }
        }
        .navigationTitle(track?.name ?? "轨迹详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)   // 二级页隐藏底部 Tab（页面结构规则）
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { renameText = track?.name ?? ""; showRename = true } label: {
                        Label("重命名", systemImage: "pencil")
                    }
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label("删除轨迹", systemImage: "trash")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .alert("重命名轨迹", isPresented: $showRename) {
            TextField("名称", text: $renameText)
            Button("保存") { renameTrack() }
            Button("取消", role: .cancel) {}
        }
        .alert("删除该轨迹？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) { deleteTrack() }
            Button("取消", role: .cancel) {}
        } message: { Text("删除后可在云端同步前恢复（三期）；本机列表将移除。") }
        .task {
            // 进入页面时一次性从仓库加载轨迹/点/航点，并派生出绘线坐标与海拔剖面
            track = try? TrackRepository().track(id: trackId)
            points = (try? TrackRepository().points(trackId: trackId)) ?? []
            waypoints = (try? TrackRepository().waypoints(trackId: trackId)) ?? []
            coords = points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            profile = Self.buildProfile(points)
        }
        .sheet(isPresented: $showShare) {
            if let exportURL { ShareSheet(items: [exportURL]) }
        }
        .confirmationDialog("导出格式", isPresented: $showExportDialog, titleVisibility: .visible) {
            Button("GPX") { export(.gpx) }
            Button("KML") { export(.kml) }
            Button("取消", role: .cancel) {}
        }
        .alert("导出失败", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(exportError ?? "") }
        .confirmationDialog("选择底图", isPresented: $showLayerSheet, titleVisibility: .visible) {
            Button("在线影像（ESRI，含已缓存离线区域）") { baseMode = .onlineRaster }
            ForEach(OfflineMaps.list().filter { OfflineMaps.isVectorBase($0) }, id: \.self) { url in
                Button("离线矢量 · \(url.deletingPathExtension().lastPathComponent)") {
                    baseMode = .offlineVector(path: url.path)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("卫星离线：在「在线影像」底图下，已下载区域断网自动显示")
        }
        .alert("编辑标注点", isPresented: $showEditWaypoint) {
            TextField("名称", text: $editWpName)
            TextField("备注（可选）", text: $editWpNote)
            Button("保存") { saveWaypointEdit() }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("更改类型", isPresented: $showKindDialog, titleVisibility: .visible) {
            ForEach(WaypointKind.allOrdered, id: \.self) { k in
                Button(k.label) { changeWaypointKind(to: k) }
            }
            Button("取消", role: .cancel) {}
        }
    }

    /// 标注点页：航点列表（点击居中、左滑删除/编辑、改类型）。
    private var waypointList: some View {
        List {
            if waypoints.isEmpty {
                Text("暂无标注点。记录途中点「打点」，或导入含航点的 GPX。")
                    .foregroundColor(AppColor.ink2).font(.subheadline)
                    .padding(.vertical, 8)
            } else {
                ForEach(waypoints) { w in
                    // 点击航点：设为居中目标并切回地图页，让地图把该点移到中心
                    Button { focusWaypoint = w; tab = 0 } label: {
                        HStack(spacing: 12) {
                            Image(systemName: w.kind.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                                .background(w.kind.color).clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.name).foregroundColor(AppColor.ink)
                                if let note = w.note, !note.isEmpty {
                                    Text(note).font(.caption).foregroundColor(AppColor.ink2)
                                } else if let e = w.elevation {
                                    Text("海拔 \(Int(e)) m").font(.caption).foregroundColor(AppColor.ink2)
                                }
                            }
                            Spacer()
                            Image(systemName: "scope").font(.caption).foregroundColor(AppColor.ink2)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { deleteWaypoint(w) } label: { Label("删除", systemImage: "trash") }
                        Button { startWaypointEdit(w) } label: { Label("编辑", systemImage: "pencil") }.tint(AppColor.info)
                    }
                    .swipeActions(edge: .leading) {
                        Button { kindPickWaypoint = w; showKindDialog = true } label: { Label("类型", systemImage: "tag") }
                            .tint(AppColor.warning)
                    }
                }
            }
        }
    }

    /// 从仓库重新拉取航点列表（增删改后刷新 UI）。
    private func reloadWaypoints() {
        waypoints = (try? TrackRepository().waypoints(trackId: trackId)) ?? []
    }
    /// 删除航点并刷新列表。
    private func deleteWaypoint(_ w: Waypoint) {
        try? TrackRepository().deleteWaypoint(id: w.id)
        reloadWaypoints()
    }
    /// 进入航点编辑：预填名称/备注并弹出编辑 alert。
    private func startWaypointEdit(_ w: Waypoint) {
        editingWaypoint = w; editWpName = w.name; editWpNote = w.note ?? ""; showEditWaypoint = true
    }
    /// 保存航点编辑（名称留空则保留原名，备注留空存 nil），刷新列表。
    private func saveWaypointEdit() {
        guard let w = editingWaypoint else { return }
        let n = editWpName.trimmingCharacters(in: .whitespaces)
        try? TrackRepository().updateWaypoint(id: w.id, name: n.isEmpty ? w.name : n,
                                              note: editWpNote.isEmpty ? nil : editWpNote, kind: w.kind)
        editingWaypoint = nil; reloadWaypoints()
    }
    /// 仅更改航点类型（名称/备注不变），刷新列表。
    private func changeWaypointKind(to kind: WaypointKind) {
        guard let w = kindPickWaypoint else { return }
        try? TrackRepository().updateWaypoint(id: w.id, name: w.name, note: w.note, kind: kind)
        kindPickWaypoint = nil; reloadWaypoints()
    }

    /// 当前是否为离线矢量底图（路网控件仅此模式显示）。
    private var isVectorBase: Bool {
        if case .offlineVector = baseMode { return true }
        return false
    }

    /// 导出格式。
    private enum ExportFormat { case gpx, kml }

    /// 导出轨迹（含航点）为指定格式 → 系统分享面板（任务 5.5）。失败填 exportError 弹错误。
    private func export(_ format: ExportFormat) {
        guard let track else { return }
        do {
            switch format {
            case .gpx: exportURL = try GPXService().export(track: track, points: points, waypoints: waypoints)
            case .kml: exportURL = try KMLService.export(track: track, points: points, waypoints: waypoints)
            }
            showShare = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    // MARK: - 地图页（抽成独立属性，避免 body 表达式过大导致编译器类型检查超时）

    /// 剖面拖选点 → 地图高亮坐标（下标越界则 nil 不高亮）。
    private var highlightCoord: CLLocationCoordinate2D? {
        guard let i = selectedProfileIndex, profile.indices.contains(i) else { return nil }
        return profile[i].coord
    }
    /// 标注点列表点击的居中目标坐标（nil 表示不居中）。
    private var centerCoord: CLLocationCoordinate2D? {
        focusWaypoint.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }
    /// 实际传给地图的航点（「标记点」开关关闭时传空隐藏）。
    private var shownWaypoints: [Waypoint] { showWaypoints ? waypoints : [] }

    /// 地图页：底图 + 控件 + 提示 + （可选）海拔剖面。
    private var mapTab: some View {
        VStack(spacing: 0) {
            ZStack {
                MapLibreView(controller: mapCtrl, baseMode: baseMode, trackCoordinates: coords,
                             showsUserLocation: true, fitToTrack: true, showKmMarkers: showKm,
                             showContours: showContours, contourPath: OfflineMaps.contourPack()?.path,
                             highlightCoordinate: highlightCoord,
                             showRoadNetwork: showRoadNetwork,
                             waypoints: shownWaypoints, centerOn: centerCoord)
                MapControlsOverlay(controller: mapCtrl, showKm: $showKm, showContours: showContours,
                                   hasProfile: !profile.isEmpty, showProfile: showProfile,
                                   isVectorBase: isVectorBase, showRoadNetwork: $showRoadNetwork,
                                   hasWaypoints: !waypoints.isEmpty, showWaypoints: $showWaypoints,
                                   onPlaceholder: showToast, onLayers: { showLayerSheet = true },
                                   onContours: { toggleContours() },
                                   onProfile: {
                                       // 切换剖面显隐；收起时清除选中点，避免地图残留高亮
                                       withAnimation { showProfile.toggle() }
                                       if !showProfile { selectedProfileIndex = nil }
                                   })
                if let toast {
                    VStack {
                        Spacer()
                        Text(toast).font(.caption).foregroundColor(.white)
                            .padding(.vertical, 8).padding(.horizontal, 14)
                            .background(Color.black.opacity(0.75)).cornerRadius(10)
                            .padding(.bottom, 24)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            // 仅有剖面数据且开关打开时，在地图下方拉出剖面（与底部按钮互斥）
            if !profile.isEmpty && showProfile {
                ElevationProfileView(samples: profile, selected: $selectedProfileIndex)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var statsList: some View {
        List {
            if let t = track {
                // 顶部封面：轨迹形状缩略图（与列表同款，较大）
                HStack { Spacer()
                    TrackThumbnailView(trackId: trackId, pointCount: t.pointCount, side: 150, corner: 14)
                    Spacer() }
                    .listRowSeparator(.hidden)
                row("距离", String(format: "%.2f km", t.distance / 1000))
                row("累计爬升", "\(Int(t.ascent)) m"); row("累计下降", "\(Int(t.descent)) m")
                row("运动用时", format(t.movingTime)); row("轨迹点数", "\(t.pointCount)")
                // TODO(5.6): 海拔剖面图（点击联动地图）
            }
        }
    }
    /// 构建海拔剖面采样（累计距离/海拔，海拔缺失则沿用上一个；下采样到 ~300 点）。无任何海拔则返回空（不显示）。
    private static func buildProfile(_ pts: [TrackPoint]) -> [ElevSample] {
        guard pts.count > 1, pts.contains(where: { $0.elevation != nil }) else { return [] }
        var raw: [(d: Double, ele: Double, c: CLLocationCoordinate2D)] = []
        var acc = 0.0, lastEle = 0.0
        var prev: CLLocation?
        for p in pts {
            let loc = CLLocation(latitude: p.lat, longitude: p.lon)
            if let prev { acc += loc.distance(from: prev) }
            prev = loc
            if let e = p.elevation { lastEle = e }
            raw.append((acc / 1000, lastEle, loc.coordinate))
        }
        let step = max(1, raw.count / 300)
        var out: [ElevSample] = []
        var i = 0
        while i < raw.count {
            out.append(ElevSample(id: out.count, d: raw[i].d, ele: raw[i].ele, coord: raw[i].c))
            i += step
        }
        if let last = raw.last, out.last?.d != last.d {
            out.append(ElevSample(id: out.count, d: last.d, ele: last.ele, coord: last.c))
        }
        return out
    }

    /// 重命名轨迹：写库成功后同步更新内存中的 track，使标题立即刷新（空名忽略）。
    private func renameTrack() {
        let n = renameText.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        try? TrackRepository().rename(id: trackId, name: n)
        track?.name = n
    }
    /// 软删除轨迹并关闭详情页（数据可在云端同步前恢复）。
    private func deleteTrack() {
        try? TrackRepository().softDelete(id: trackId)
        dismiss()
    }
    /// 切换等高线：未导入等高线包时给出提示而非切换，避免开了开关却看不到东西。
    private func toggleContours() {
        if OfflineMaps.contourPack() == nil { showToast("未导入等高线包（我的 → 离线地图 导入 *contour*.pmtiles）") }
        else { showContours.toggle() }
    }
    /// 显示一条 1.5s 自动消失的轻提示；用闭包内比对防止后续提示被旧的清空覆盖。
    private func showToast(_ msg: String) {
        toast = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if toast == msg { toast = nil } }
    }
    private func row(_ l: String, _ v: String) -> some View { HStack { Text(l); Spacer(); Text(v).foregroundColor(AppColor.ink2) } }
    private func format(_ s: TimeInterval) -> String { let h = Int(s)/3600, m = (Int(s)%3600)/60; return String(format: "%02d:%02d", h, m) }
}
