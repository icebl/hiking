import SwiftUI
import CoreLocation

/// 轨迹详情（任务 6.2 / 5.6）：地图 / 详情 页签 + 操作（导出/导航）。
struct TrackDetailView: View {
    let trackId: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0       // 0 地图 / 1 详情
    @State private var track: Track?
    @State private var points: [TrackPoint] = []
    @State private var waypoints: [Waypoint] = []
    @State private var coords: [CLLocationCoordinate2D] = []
    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var exportError: String?
    @StateObject private var mapCtrl = MapController()
    @State private var showKm = false
    @State private var showContours = false
    @State private var showRoadNetwork = false
    @State private var toast: String?
    @State private var baseMode: MapBaseMode = .onlineRaster
    @State private var showLayerSheet = false
    @State private var profile: [ElevSample] = []
    @State private var selectedProfileIndex: Int?
    @State private var showProfile = false           // 默认不展开海拔剖面
    @State private var showWaypoints = true          // 轨迹上标记点显隐
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    // 标注点（航点）管理
    @State private var focusWaypoint: Waypoint?         // 列表点击 → 地图居中目标
    @State private var editingWaypoint: Waypoint?
    @State private var editWpName = ""
    @State private var editWpNote = ""
    @State private var showEditWaypoint = false
    @State private var kindPickWaypoint: Waypoint?
    @State private var showKindDialog = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) { Text("地图").tag(0); Text("详情").tag(1); Text("标注点").tag(2) }
                .pickerStyle(.segmented).padding()

            if tab == 0 {
                VStack(spacing: 0) {
                    ZStack {
                        MapLibreView(controller: mapCtrl, baseMode: baseMode, trackCoordinates: coords,
                                     showsUserLocation: true, fitToTrack: true, showKmMarkers: showKm,
                                     showContours: showContours, contourPath: OfflineMaps.contourPack()?.path,
                                     highlightCoordinate: selectedProfileIndex.flatMap {
                                         profile.indices.contains($0) ? profile[$0].coord : nil },
                                     showRoadNetwork: showRoadNetwork,
                                     waypoints: showWaypoints ? waypoints : [],
                                     centerOn: focusWaypoint.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) })
                        MapControlsOverlay(controller: mapCtrl, showKm: $showKm, showContours: showContours,
                                           hasProfile: !profile.isEmpty, showProfile: showProfile,
                                           isVectorBase: isVectorBase, showRoadNetwork: $showRoadNetwork,
                                           hasWaypoints: !waypoints.isEmpty, showWaypoints: $showWaypoints,
                                           onPlaceholder: showToast, onLayers: { showLayerSheet = true },
                                           onContours: { toggleContours() },
                                           onProfile: {
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
                    if !profile.isEmpty && showProfile {
                        ElevationProfileView(samples: profile, selected: $selectedProfileIndex)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            } else if tab == 1 {
                statsList
            } else {
                waypointList
            }

            // 标记点页隐藏底部按钮；地图页展开剖面时也隐藏（给剖面让空间）。
            if tab != 2 && !(tab == 0 && showProfile && !profile.isEmpty) {
                HStack(spacing: 12) {
                    Button { exportGPX() } label: {
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
            track = try? TrackRepository().track(id: trackId)
            points = (try? TrackRepository().points(trackId: trackId)) ?? []
            waypoints = (try? TrackRepository().waypoints(trackId: trackId)) ?? []
            coords = points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            profile = Self.buildProfile(points)
        }
        .sheet(isPresented: $showShare) {
            if let exportURL { ShareSheet(items: [exportURL]) }
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

    private func reloadWaypoints() {
        waypoints = (try? TrackRepository().waypoints(trackId: trackId)) ?? []
    }
    private func deleteWaypoint(_ w: Waypoint) {
        try? TrackRepository().deleteWaypoint(id: w.id)
        reloadWaypoints()
    }
    private func startWaypointEdit(_ w: Waypoint) {
        editingWaypoint = w; editWpName = w.name; editWpNote = w.note ?? ""; showEditWaypoint = true
    }
    private func saveWaypointEdit() {
        guard let w = editingWaypoint else { return }
        let n = editWpName.trimmingCharacters(in: .whitespaces)
        try? TrackRepository().updateWaypoint(id: w.id, name: n.isEmpty ? w.name : n,
                                              note: editWpNote.isEmpty ? nil : editWpNote, kind: w.kind)
        editingWaypoint = nil; reloadWaypoints()
    }
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

    /// 导出 GPX（含航点）→ 系统分享面板（任务 5.5）。
    private func exportGPX() {
        guard let track else { return }
        do {
            exportURL = try GPXService().export(track: track, points: points, waypoints: waypoints)
            showShare = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    private var statsList: some View {
        List {
            if let t = track {
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

    private func renameTrack() {
        let n = renameText.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        try? TrackRepository().rename(id: trackId, name: n)
        track?.name = n
    }
    private func deleteTrack() {
        try? TrackRepository().softDelete(id: trackId)
        dismiss()
    }
    private func toggleContours() {
        if OfflineMaps.contourPack() == nil { showToast("未导入等高线包（我的 → 离线地图 导入 *contour*.pmtiles）") }
        else { showContours.toggle() }
    }
    private func showToast(_ msg: String) {
        toast = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if toast == msg { toast = nil } }
    }
    private func row(_ l: String, _ v: String) -> some View { HStack { Text(l); Spacer(); Text(v).foregroundColor(AppColor.ink2) } }
    private func format(_ s: TimeInterval) -> String { let h = Int(s)/3600, m = (Int(s)%3600)/60; return String(format: "%02d:%02d", h, m) }
}
