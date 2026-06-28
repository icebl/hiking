import SwiftUI
import UIKit
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
    @State private var showWaypoints = false         // 轨迹上标记点显隐（默认关）
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
    @State private var viewerImage: UIImage?            // 正在全屏查看的航点照片（nil=不显示）
    @State private var showTrim = false                 // 裁剪首尾页

    // 工具箱（同地图页）：取点 / 测距 / 面积 / 距离雷达
    enum MeasureMode { case none, distance, area }
    @State private var measure: MeasureMode = .none
    @State private var measurePoints: [CLLocationCoordinate2D] = []
    @State private var showRadar = false
    @State private var pickingCoord = false             // 取点模式
    @State private var showToolSheet = false
    @State private var tapped: String?                  // 取点经纬度读数
    @State private var tappedCoord: CLLocationCoordinate2D?
    @State private var tappedEle = "海拔 查询中…"
    @State private var tappedCopied = false

    // body 拆分：导航栏修饰留在 body，内容与各类弹窗下放到 content/子视图，
    // 避免单个表达式过大触发「类型检查超时」。
    var body: some View {
        content
            .navigationTitle(track?.name ?? "轨迹详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)   // 二级页隐藏底部 Tab（页面结构规则）
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { renameText = track?.name ?? ""; showRename = true } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        // 轨迹编辑：均另存为新轨迹，原轨迹保留
                        Button { reverseSave() } label: { Label("反向另存", systemImage: "arrow.uturn.left") }
                        Button { splitSegments() } label: { Label("按段拆分", systemImage: "scissors") }
                        Button { showTrim = true } label: { Label("裁剪首尾", systemImage: "crop") }
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("删除轨迹", systemImage: "trash")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
    }

    /// 页面主体：分段内容 + 底部按钮，挂数据加载与「重命名/删除/导出」相关弹窗。
    private var content: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) { Text("地图").tag(0); Text("详情").tag(1); Text("标注点").tag(2) }
                .pickerStyle(.segmented).padding()
            if tab == 0 { mapTab } else if tab == 1 { statsList } else { waypointList }
            bottomActions
        }
        .task {
            // 进入页面时一次性从仓库加载轨迹/点/航点，并派生出绘线坐标与海拔剖面
            track = try? TrackRepository().track(id: trackId)
            points = (try? TrackRepository().points(trackId: trackId)) ?? []
            waypoints = (try? TrackRepository().waypoints(trackId: trackId)) ?? []
            coords = points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            profile = Self.buildProfile(points)
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
        .sheet(isPresented: $showShare) {
            if let exportURL { ShareSheet(items: [exportURL]) }
        }
        .sheet(isPresented: $showTrim) {
            NavigationStack { TrackTrimView(trackId: trackId) { showToast("已保存裁剪轨迹（在列表查看）") } }
        }
        .confirmationDialog("导出格式", isPresented: $showExportDialog, titleVisibility: .visible) {
            Button("GPX") { export(.gpx) }
            Button("KML") { export(.kml) }
            Button("取消", role: .cancel) {}
        }
        .alert("导出失败", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(exportError ?? "") }
    }

    /// 底部按钮（导出 / 使用轨迹导航）。标记点页隐藏；地图页展开剖面时也隐藏（给剖面让空间）。
    @ViewBuilder private var bottomActions: some View {
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

    /// 标注点页：航点列表（点击居中、左滑删除/编辑、改类型）。
    private var waypointList: some View {
        List {
            if waypoints.isEmpty {
                Text("暂无标注点。记录途中点「打点」，或导入含航点的 GPX。")
                    .foregroundColor(AppColor.ink2).font(.subheadline)
                    .padding(.vertical, 8)
            } else {
                ForEach(waypoints) { w in
                    // 行点击居中地图；前导若有照片则显示缩略图（点缩略图看大图，不触发居中）
                    HStack(spacing: 12) {
                        wpLeading(w)
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
                    .onTapGesture { focusWaypoint = w; tab = 0 }
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
        // 航点编辑/改类型弹窗下放到本页（触发源在此列表），分担 body 的类型检查负担
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
        // 航点照片全屏查看
        .fullScreenCover(isPresented: Binding(get: { viewerImage != nil },
                                              set: { if !$0 { viewerImage = nil } })) {
            photoViewer
        }
    }

    /// 航点行前导：有照片显示缩略图（点开看大图），否则显示类型彩色图标圆。
    @ViewBuilder private func wpLeading(_ w: Waypoint) -> some View {
        if let img = WaypointPhotoStore.load(w.id) {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 7))
                .onTapGesture { viewerImage = img }
        } else {
            Image(systemName: w.kind.icon)
                .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                .frame(width: 30, height: 30).background(w.kind.color).clipShape(Circle())
        }
    }

    /// 照片全屏查看器：黑底等比展示 + 右上关闭。
    @ViewBuilder private var photoViewer: some View {
        if let img = viewerImage {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                Image(uiImage: img).resizable().scaledToFit().ignoresSafeArea()
                Button { viewerImage = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 30)).foregroundColor(.white.opacity(0.9))
                }.padding()
            }
        }
    }

    /// 从仓库重新拉取航点列表（增删改后刷新 UI）。
    private func reloadWaypoints() {
        waypoints = (try? TrackRepository().waypoints(trackId: trackId)) ?? []
    }
    /// 删除航点并刷新列表；一并清理其照片文件。
    private func deleteWaypoint(_ w: Waypoint) {
        try? TrackRepository().deleteWaypoint(id: w.id)
        WaypointPhotoStore.delete(w.id)
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
                             highlightCoordinate: tappedCoord ?? highlightCoord,   // 取点高亮优先于剖面高亮
                             measureCoordinates: measurePoints, measureIsArea: measure == .area, showRadar: showRadar,
                             showRoadNetwork: showRoadNetwork,
                             waypoints: shownWaypoints, centerOn: centerCoord,
                             onTap: { c in
                                 // 测距/面积→落点；取点→经纬度+海拔+高亮；否则忽略
                                 if measure != .none { measurePoints.append(c) }
                                 else if pickingCoord {
                                     tapped = CoordFormatter.string(c, format: AppSettings.coordFormat)
                                     tappedCoord = c
                                     fetchTappedElevation(c)
                                 }
                             })
                MapControlsOverlay(controller: mapCtrl, showKm: $showKm, showContours: showContours,
                                   hasProfile: !profile.isEmpty, showProfile: showProfile,
                                   isVectorBase: isVectorBase, showRoadNetwork: $showRoadNetwork,
                                   hasWaypoints: !waypoints.isEmpty, showWaypoints: $showWaypoints,
                                   toolsActive: measure != .none || showRadar || pickingCoord,
                                   onTools: { showToolSheet = true },
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
                // 指北针（旋转时显示、点击回正北）+ 比例尺标尺，避开左侧控件
                CompassButton(controller: mapCtrl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 72).padding(.leading, 14)
                ScaleBarView(controller: mapCtrl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 16).padding(.bottom, 12)
                // 取点模式提示（未取点时）
                if pickingCoord && tapped == nil {
                    Text("点击地图取经纬度").font(.caption).foregroundColor(.white)
                        .padding(.vertical, 5).padding(.horizontal, 12)
                        .background(AppColor.primary.opacity(0.9)).cornerRadius(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, 8)
                }
                // 工具箱：测量条 / 取点读数（底部）
                VStack(spacing: 8) {
                    Spacer()
                    if measure != .none { measureBar }
                    if tapped != nil { tappedReadout }
                }.padding(.horizontal, 12).padding(.bottom, 12)
            }
            .frame(maxHeight: .infinity)
            // 仅有剖面数据且开关打开时，在地图下方拉出剖面（与底部按钮互斥）
            if !profile.isEmpty && showProfile {
                ElevationProfileView(samples: profile, selected: $selectedProfileIndex)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // 底图选择弹窗下放到地图页（触发源在地图控件「图层」），分担 body 类型检查负担
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
        // 工具箱（同地图页）：取点/测距/面积/距离雷达互斥切换
        .confirmationDialog("工具箱", isPresented: $showToolSheet, titleVisibility: .visible) {
            Button("取点（经纬度）") { measure = .none; measurePoints = []; clearTapped(); pickingCoord = true }
            Button("测距") { measure = .distance; measurePoints = []; clearTapped(); pickingCoord = false }
            Button("面积") { measure = .area; measurePoints = []; clearTapped(); pickingCoord = false }
            Button(showRadar ? "关闭距离雷达" : "距离雷达") { showRadar.toggle() }
            if measure != .none { Button("退出测量", role: .destructive) { measure = .none; measurePoints = [] } }
            if pickingCoord { Button("退出取点", role: .destructive) { exitPicking() } }
            Button("取消", role: .cancel) {}
        } message: { Text("取点：点地图取经纬度；测距/面积：连点测量；距离雷达：以定位为中心同心圈") }
    }

    /// 测量结果条（测距/面积）：读数 + 后退/清除/退出。
    private var measureBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(measure == .area ? "面积" : "测距").font(.caption).foregroundColor(.white.opacity(0.8))
                Text(measure == .area ? Measure.areaText(Measure.polygonArea(measurePoints))
                                      : Measure.distanceText(Measure.totalDistance(measurePoints)))
                    .font(.system(size: 16, weight: .bold)).foregroundColor(.white)
            }
            Spacer()
            Button { if !measurePoints.isEmpty { measurePoints.removeLast() } } label: {
                Image(systemName: "arrow.uturn.backward").foregroundColor(.white).frame(width: 40, height: 40)
            }.disabled(measurePoints.isEmpty)
            Button { measurePoints = [] } label: { Text("清除").foregroundColor(.white).frame(width: 48, height: 40) }
            Button { measure = .none; measurePoints = [] } label: { Text("退出").foregroundColor(AppColor.recording).frame(width: 48, height: 40) }
        }
        .font(.subheadline)
        .padding(.vertical, 6).padding(.leading, 14).padding(.trailing, 6)
        .background(Color.black.opacity(0.78)).cornerRadius(12)
    }

    /// 取点经纬度读数：经纬度 + 海拔 + 复制 + 关闭（X 退出取点模式）。
    private var tappedReadout: some View {
        HStack {
            (Text("点 ").foregroundColor(.white)
             + Text(tapped ?? "").foregroundColor(Color(hex: 0x7EE0A6)).bold()
             + Text(" · \(tappedEle)").foregroundColor(.white)).font(.caption)
            Spacer()
            Button { copyTapped() } label: {
                HStack(spacing: 3) {
                    Image(systemName: tappedCopied ? "checkmark" : "doc.on.doc")
                    Text(tappedCopied ? "已复制" : "复制")
                }.font(.caption).foregroundColor(tappedCopied ? Color(hex: 0x7EE0A6) : .white)
            }
            Button { exitPicking() } label: {
                Image(systemName: "xmark").foregroundColor(.white.opacity(0.8))
            }.padding(.leading, 12)
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .background(Color.black.opacity(0.78)).cornerRadius(12)
    }

    /// 异步查点击点海拔（在线 DEM）。
    private func fetchTappedElevation(_ c: CLLocationCoordinate2D) {
        tappedEle = "海拔 查询中…"
        Task { @MainActor in
            if let e = await ElevationService.shared.elevation(lat: c.latitude, lon: c.longitude) {
                tappedEle = String(format: "海拔 %.0f m", e)
            } else { tappedEle = "海拔 未知" }
        }
    }
    /// 复制经纬度（仅经纬度）到剪贴板。
    private func copyTapped() {
        guard let tapped else { return }
        UIPasteboard.general.string = tapped
        withAnimation { tappedCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { tappedCopied = false } }
    }
    private func clearTapped() { tapped = nil; tappedCoord = nil }
    private func exitPicking() { clearTapped(); pickingCoord = false }

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
    /// 反向另存为新轨迹。
    private func reverseSave() {
        do {
            if try TrackEditor.reverseSave(trackId) != nil { showToast("已另存反向轨迹（在列表查看）") }
            else { showToast("点数不足，无法反向") }
        } catch { showToast("操作失败") }
    }
    /// 按段拆分为多条新轨迹（单段则提示无法拆分）。
    private func splitSegments() {
        do {
            let n = try TrackEditor.splitBySegment(trackId)
            showToast(n > 1 ? "已拆为 \(n) 段（在列表查看）" : "只有一段，无法拆分")
        } catch { showToast("操作失败") }
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
