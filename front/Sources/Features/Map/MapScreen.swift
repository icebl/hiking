import SwiftUI
import UIKit
import CoreLocation

/// 地图（全屏沉浸，任务 2.x）：底图 + 悬浮控件 + 居中信息条 + 底部记录/导航 + 点击取经纬度。
/// 控件布局对齐 UI/视觉稿/原型.html：
///   左列：返回 / 定位键（居中→跟随循环）
///   右列：图层 / 叠加 / 工具 / 缩放(+/-) / 缩放滑块 / 公里标
struct MapScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var mapCtrl = MapController()      // 地图实例与缩放/定位状态的桥接控制器
    @ObservedObject private var loc = LocationManager.shared  // 实时定位（驱动顶部信息条经纬度/海拔）
    @State private var showRecording = false               // 是否弹出全屏「记录」页
    @State private var tapped: String? = nil   // 点击地图取经纬度读数（任务 2.8）；nil 表示未点/已关闭
    @State private var tappedEle: String = "海拔 查询中…"   // 点击点的海拔（DEM 在线查，异步回填）
    @State private var tappedCoord: CLLocationCoordinate2D? // 点击点坐标，用于地图高亮标记
    @State private var tappedCopied = false                 // 复制经纬度后短暂反馈
    @State private var pickingCoord = false                 // 取点模式（工具箱启用）：点地图才取经纬度
    @State private var probeCoord: CLLocationCoordinate2D?   // 长按测距：目标点（地图高亮）
    @State private var probeText: String?                   // 长按测距：距我/方位读数
    @State private var zoomLevel: Double = 0.5  // 缩放滑块位置（0…1），1=最大
    @State private var zoomDragging = false     // 缩放滑块拖动中（控制左侧数值气泡显隐）
    @AppStorage("highContrastMap") private var highContrast = false  // 高对比地图文字（强光可读性）
    @State private var showKm = false           // 公里标开关
    @State private var showContours = false      // 等高线开关
    @State private var showRoadNetwork = false   // 路网开关（仅离线矢量底图有效）
    @State private var baseMode: MapBaseMode = .onlineRaster(.satellite)  // 当前底图：默认在线影像，可切地形/街道/离线矢量
    @State private var showLayerSheet = false                // 是否弹出底图选择对话框
    // 工具箱：测距 / 面积 / 距离雷达
    enum MeasureMode { case none, distance, area }           // 测量模式：无 / 测距(折线) / 面积(多边形)
    @State private var measure: MeasureMode = .none
    @State private var measurePoints: [CLLocationCoordinate2D] = []  // 测量时按点击顺序累积的坐标点
    @State private var showRadar = false                     // 距离雷达（以当前定位为中心的同心圈）开关
    @State private var showToolSheet = false                 // 是否弹出工具箱对话框
    // 多轨迹叠加：选中的轨迹 id 集合 + 有序叠加项（含名称/坐标）；颜色按 overlayItems 下标稳定分配
    @State private var showOverlaySheet = false              // 是否弹出叠加轨迹选择面板
    @State private var overlaySelection: Set<UUID> = []      // 当前勾选叠加的轨迹 id
    @State private var overlayItems: [OverlayItem] = []      // 有序叠加项（顺序=颜色下标=图例顺序）

    var body: some View {
        ZStack {
            // 底图视图：把上面各开关/状态下传给原生地图渲染
            MapLibreView(controller: mapCtrl, baseMode: baseMode, showKmMarkers: showKm,
                         showContours: showContours, contourPath: OfflineMaps.contourPack()?.path,
                         highlightCoordinate: probeCoord ?? tappedCoord,   // 长按测距点优先，其次取点高亮（橙点）
                         measureCoordinates: measurePoints, measureIsArea: measure == .area, showRadar: showRadar,
                         showRoadNetwork: showRoadNetwork, overlays: overlayItems.map(\.coords),
                         onTap: { c in
                             // 测量中→落测量点；取点模式→取经纬度+查海拔+高亮；都不是→忽略点击
                             if measure != .none { measurePoints.append(c) }
                             else if pickingCoord {
                                 tapped = CoordFormatter.string(c, format: AppSettings.coordFormat)
                                 tappedCoord = c
                                 fetchTappedElevation(c)
                             }
                         },
                         onLongPress: { c in probeDistance(c) })   // 长按：该点距我直线距离/方位
                .ignoresSafeArea()

            // 信息条：靠上居中（WGS84 浅绿高亮）；取点模式且未取点时提示点击地图
            VStack(spacing: 6) {
                infoBar
                if pickingCoord && tapped == nil {
                    Text("点击地图取经纬度").font(.caption).foregroundColor(.white)
                        .padding(.vertical, 5).padding(.horizontal, 12)
                        .background(AppColor.primary.opacity(0.9)).cornerRadius(10)
                }
                Spacer()
            }
            .padding(.top, 6)

            // 左列：返回（顶）/ 定位键（中）
            HStack {
                VStack(spacing: 0) {
                    ctrl("chevron.left") { dismiss() }
                    Spacer()
                    locateButton
                    Spacer()
                }
                Spacer()
            }
            .padding(.leading, 14)
            .padding(.top, 6)
            .padding(.bottom, 120)

            // 右列：图层 / 叠加 / 工具（顶）— 缩放 +/- + 滑块（中）— 公里标（下）
            HStack {
                Spacer()
                VStack(spacing: 14) {
                    ctrl("square.3.stack.3d", "图层") { showLayerSheet = true }   // 切底图：在线影像/离线矢量
                    ctrl("square.on.square", "叠加", active: !overlayItems.isEmpty) { showOverlaySheet = true }
                    ctrl("wrench.and.screwdriver", "工具", active: measure != .none || showRadar || pickingCoord) { showToolSheet = true }
                    Spacer()
                    VStack(spacing: 8) {                       // 缩放：+/- 与滑块同一区
                        zoomGroup
                        zoomSlider
                    }
                    Spacer()
                    ctrl("mountain.2", "等高线", active: showContours) { toggleContours() }
                    if isVectorBase {
                        ctrl("point.topleft.down.curvedto.point.bottomright.up", "路网",
                             active: showRoadNetwork) { showRoadNetwork.toggle() }
                    }
                    // 公里标仅在「轨迹详情」地图（有轨迹）显示，主地图不放
                }
            }
            .padding(.trailing, 14)
            .padding(.top, 6)
            .padding(.bottom, 120)

            // 点击经纬度读数（带关闭）
            if let tapped {
                VStack {
                    Spacer()
                    HStack {
                        Text("地图上的点 ")
                            .foregroundColor(.white)
                        + Text(tapped).foregroundColor(Color(hex: 0x7EE0A6)).bold()
                        + Text(" · \(tappedEle)").foregroundColor(.white)
                        Spacer()
                        // 复制：把经纬度(含海拔)写入剪贴板，便于粘到微信/备忘录
                        Button { copyTapped() } label: {
                            HStack(spacing: 3) {
                                Image(systemName: tappedCopied ? "checkmark" : "doc.on.doc")
                                Text(tappedCopied ? "已复制" : "复制")
                            }.foregroundColor(tappedCopied ? Color(hex: 0x7EE0A6) : .white)
                        }
                        Button { exitPicking() } label: {   // 关闭：移除高亮标记并退出取点模式
                            Image(systemName: "xmark").foregroundColor(.white.opacity(0.8))
                        }.padding(.leading, 12)
                    }
                    .font(.caption)
                    .padding(.vertical, 10).padding(.horizontal, 14)
                    .frame(maxWidth: .infinity)
                    .background(AppColor.mapScrim(highContrast))
                }
                .padding(.bottom, 96)
            }

            // 底部：测量条（测距/面积时）+ 叠加图例（有叠加时）+ 记录 / 导航
            VStack {
                Spacer()
                if measure != .none { measureBar.padding(.horizontal, 16).padding(.bottom, 8) }
                if probeText != nil { probeBar.padding(.horizontal, 16).padding(.bottom, 8) }
                if !overlayItems.isEmpty { overlayLegend.padding(.horizontal, 16).padding(.bottom, 8) }
                HStack(spacing: 12) {
                    Button { showRecording = true } label: { cta("记录", "record.circle", .white, AppColor.ink) }
                    // 导航按钮暂时隐藏（功能保留，待 4.5 选轨迹进入导航后再开放）
                    if false {
                        Button { /* TODO(4.5): 选轨迹进入导航 */ } label: { cta("导航", "location.north.line.fill", AppColor.primary, .white) }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 30)
            }

            // 指北针（旋转时显示、点击回正北）：左上，避开返回按钮
            CompassButton(controller: mapCtrl)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 60).padding(.leading, 14)
            // 比例尺标尺：左下，避开底部按钮
            ScaleBarView(controller: mapCtrl)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 16).padding(.bottom, 104)
        }
        .fullScreenCover(isPresented: $showRecording) { RecordingView() }
        // 进入主地图即前台定位（驱动信息条实时经纬度/海拔）；离开页面停止以省电。
        // 注：记录/导航页各自管理后台定位，互不影响（最后一次 start 的配置生效）。
        .onAppear { loc.requestWhenInUse(); loc.start(background: false) }
        .onDisappear { loc.stop() }
        // 工具箱对话框：取点/测距/面积三者互斥（都吃点击），切换时互相清理，避免状态串扰
        .confirmationDialog("工具箱", isPresented: $showToolSheet, titleVisibility: .visible) {
            Button("取点（经纬度）") { measure = .none; measurePoints = []; clearTapped(); pickingCoord = true }
            Button("测距") { measure = .distance; measurePoints = []; clearTapped(); pickingCoord = false }
            Button("面积") { measure = .area; measurePoints = []; clearTapped(); pickingCoord = false }
            Button(showRadar ? "关闭距离雷达" : "距离雷达") { showRadar.toggle() }
            if measure != .none { Button("退出测量", role: .destructive) { measure = .none; measurePoints = [] } }
            if pickingCoord { Button("退出取点", role: .destructive) { exitPicking() } }
            Button("取消", role: .cancel) {}
        } message: { Text("取点：点地图取经纬度；测距/面积：连点测量；距离雷达：以定位为中心同心圈") }
        // 底图选择对话框：固定一项在线影像 + 动态列出本地已导入的矢量包
        .confirmationDialog("选择底图", isPresented: $showLayerSheet, titleVisibility: .visible) {
            // 在线源：卫星影像 / 地形图 / 街道图（ESRI）
            ForEach(OnlineBaseSource.allCases, id: \.self) { src in
                Button(src == .satellite ? "在线影像（含已缓存离线区域）" : src.label) { baseMode = .onlineRaster(src) }
            }
            ForEach(OfflineMaps.list().filter { OfflineMaps.isVectorBase($0) }, id: \.self) { url in
                Button("离线矢量 · \(url.deletingPathExtension().lastPathComponent)") {
                    baseMode = .offlineVector(path: url.path)   // 切到该矢量包作为底图
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("卫星离线：在「在线影像」底图下，已框选下载的区域断网自动显示")
        }
        // 叠加轨迹选择面板：多选已存轨迹 → 应用后加载坐标并框住范围
        .sheet(isPresented: $showOverlaySheet) {
            OverlayPickerView(selection: $overlaySelection) { loadOverlays() }
        }
    }

    /// 按当前勾选加载有序叠加项（用 listTracks 顺序保证稳定→颜色不乱跳），并框住全部范围。
    /// 点数 <2 的轨迹跳过；空选则清空叠加。
    private func loadOverlays() {
        let repo = TrackRepository()
        let all = (try? repo.listTracks()) ?? []
        overlayItems = all.filter { overlaySelection.contains($0.id) }.compactMap { t in
            let pts = (try? repo.points(trackId: t.id)) ?? []
            guard pts.count > 1 else { return nil }
            return OverlayItem(id: t.id, name: t.name,
                               coords: pts.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) })
        }
        fitToOverlays()
    }

    /// 从图例移除单条叠加：同时从勾选集合剔除，地图与图例随 overlayItems 变化刷新。
    private func removeOverlay(_ id: UUID) {
        overlaySelection.remove(id)
        overlayItems.removeAll { $0.id == id }
    }

    /// 把相机框到所有叠加轨迹的外接矩形（有叠加时）。
    private func fitToOverlays() {
        let all = overlayItems.flatMap { $0.coords }
        guard let first = all.first else { return }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in all {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        mapCtrl.fit(sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
                    ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon))
    }

    // MARK: - 子组件

    /// 叠加图例：列出每条叠加轨迹的颜色块 + 名称 + 移除按钮（颜色与地图折线同源、按下标对应）。
    /// 条目多时纵向滚动，限制最大高度避免遮挡过多地图。
    private var overlayLegend: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("叠加轨迹 \(overlayItems.count)").font(.caption).foregroundColor(.white.opacity(0.8))
                Spacer()
                Button { overlaySelection.removeAll(); overlayItems = [] } label: {
                    Text("全部移除").font(.caption).foregroundColor(AppColor.recording)
                }
            }
            .padding(.bottom, 6)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(overlayItems.enumerated()), id: \.element.id) { idx, item in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 2).fill(OverlayPalette.color(idx))
                                .frame(width: 16, height: 4)              // 颜色块（对应地图折线色）
                            Text(item.name).font(.caption).foregroundColor(.white).lineLimit(1)
                            Spacer()
                            Button { removeOverlay(item.id) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 132)   // 约 4~5 条，超出滚动
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .background(AppColor.mapScrim(highContrast)).cornerRadius(12)
    }

    /// 长按测距读数条：「距我 距离 · 方位 …」+ 关闭（清除高亮）。
    private var probeBar: some View {
        HStack {
            (Text("距我 ").foregroundColor(.white)
             + Text(probeText ?? "").foregroundColor(Color(hex: 0x7EE0A6)).bold()).font(.caption)
            Spacer()
            Button { probeText = nil; probeCoord = nil } label: {
                Image(systemName: "xmark").foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .background(AppColor.mapScrim(highContrast)).cornerRadius(12)
    }

    /// 长按某点：算该点距当前定位的直线距离与方位，显示读数 + 地图高亮。
    private func probeDistance(_ c: CLLocationCoordinate2D) {
        probeCoord = c
        guard let me = loc.location?.coordinate else { probeText = "定位未就绪"; return }
        let d = CLLocation(latitude: me.latitude, longitude: me.longitude)
            .distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
        let brg = Measure.bearing(from: me, to: c)
        probeText = "\(Measure.distanceText(d)) · 方位 \(Measure.bearingText(brg))"
    }

    /// 当前是否为离线矢量底图（路网/标注仅此模式有效）。
    private var isVectorBase: Bool {
        if case .offlineVector = baseMode { return true }
        return false
    }

    /// 清除当前取点读数与高亮标记（不改变取点模式开关）。
    private func clearTapped() { tapped = nil; tappedCoord = nil }

    /// 退出取点模式：清读数/高亮 + 关模式（读数条 X 与工具箱「退出取点」共用）。
    private func exitPicking() { clearTapped(); pickingCoord = false }

    /// 复制点击点的经纬度（仅经纬度，不含海拔）到系统剪贴板，并短暂反馈"已复制"。
    private func copyTapped() {
        guard let tapped else { return }
        UIPasteboard.general.string = tapped
        withAnimation { tappedCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { tappedCopied = false }
        }
    }

    /// 异步查询点击点的海拔（在线 DEM）：先显示"查询中"，得到结果回填米数或"未知"。
    private func fetchTappedElevation(_ c: CLLocationCoordinate2D) {
        tappedEle = "海拔 查询中…"
        Task { @MainActor in
            if let e = await ElevationService.shared.elevation(lat: c.latitude, lon: c.longitude) {
                tappedEle = String(format: "海拔 %.0f m", e)
            } else {
                tappedEle = "海拔 未知"
            }
        }
    }

    /// 切换等高线：缺等高线包时不切换，借用经纬度读数条提示去导入；有包才真正开关。
    private func toggleContours() {
        if OfflineMaps.contourPack() == nil {
            tapped = "未导入等高线包（我的 → 离线地图 导入 *contour*.pmtiles）"
        } else {
            showContours.toggle()
        }
    }

    /// 测量结果条（测距/面积模式时显示在底部）：左侧实时读数，右侧后退/清除/退出。
    private var measureBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(measure == .area ? "面积" : "测距").font(.caption).foregroundColor(.white.opacity(0.8))
                // 按当前模式选用多边形面积或折线总长，再格式化为带单位文本
                Text(measure == .area ? Measure.areaText(Measure.polygonArea(measurePoints))
                                      : Measure.distanceText(Measure.totalDistance(measurePoints)))
                    .font(.system(size: 18, weight: .bold)).foregroundColor(.white)
            }
            Spacer()
            // 后退 / 清除 / 退出：间距加大 + 各自加大点击区，避免误触
            HStack(spacing: 10) {
                Button { if !measurePoints.isEmpty { measurePoints.removeLast() } } label: {
                    Image(systemName: "arrow.uturn.backward").foregroundColor(.white)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.disabled(measurePoints.isEmpty)
                Button { measurePoints = [] } label: {
                    Text("清除").foregroundColor(.white)
                        .frame(width: 52, height: 44).contentShape(Rectangle())
                }
                Button { measure = .none; measurePoints = [] } label: {
                    Text("退出").foregroundColor(AppColor.recording)
                        .frame(width: 52, height: 44).contentShape(Rectangle())
                }
            }
        }
        .font(.subheadline)
        .padding(.vertical, 6).padding(.leading, 14).padding(.trailing, 6)
        .background(AppColor.mapScrim(highContrast)).cornerRadius(12)
    }

    /// 顶部信息条：坐标系标识 + 示例经纬度/海拔（当前为占位静态文案，待接入实时定位）。
    /// 顶部信息条：WGS84 标签 + 实时经纬度/海拔；定位未就绪时显示「定位中…」。
    /// 经纬度恒用十进制度（与 WGS84 标签匹配，紧凑不溢出）；海拔取 GPS 椭球高，单位米。
    private var infoBar: some View {
        let prefix = Text("WGS84").foregroundColor(Color(hex: 0x7EE0A6)).fontWeight(.bold)
        let body: Text = {
            if let l = loc.location {
                return Text(" \(CoordFormatter.decimal(l.coordinate)) · 海拔\(Int(l.altitude))m")
                    .foregroundColor(.white)
            }
            return Text(" 定位中…").foregroundColor(.white)
        }()
        return (prefix + body)
            .font(.system(size: 11.5, weight: highContrast ? .bold : .medium))   // 高对比加粗
            .padding(.vertical, 6).padding(.horizontal, 14)
            .background(AppColor.mapScrim(highContrast)).cornerRadius(12)
    }

    /// 缩放 +/- 竖排药丸
    private var zoomGroup: some View {
        VStack(spacing: 0) {
            Button { mapCtrl.zoomIn() } label: {
                Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColor.ink).frame(width: 36, height: 36)
            }
            Rectangle().fill(AppColor.divider).frame(width: 36, height: 1)
            Button { mapCtrl.zoomOut() } label: {
                Image(systemName: "minus").font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColor.ink).frame(width: 36, height: 36)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }

    /// 缩放滑块（上滑放大 / 下滑缩小）；绿色圆点内显示当前缩放级别（取代原顶部读数）。
    /// 加长滑轨；绿点滑块不再放数字，拖动时数值在滑块左侧白气泡显示（避免被手指遮挡）。
    private var zoomSlider: some View {
        let trackH: CGFloat = 220, thumb: CGFloat = 28
        let y = CGFloat(1 - zoomLevel) * (trackH - thumb)   // 圆点在轨道内的纵向位置
        return ZStack(alignment: .top) {
            Capsule().fill(Color.white.opacity(0.6)).frame(width: 4, height: trackH)
            // 拖动中：数值气泡在滑块左侧
            if zoomDragging {
                Text(String(format: "%.1f", mapCtrl.zoom))
                    .font(.system(size: 14, weight: .bold)).foregroundColor(AppColor.ink)
                    .padding(.vertical, 5).padding(.horizontal, 10)
                    .background(Color.white).cornerRadius(9)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    .offset(x: -48, y: y + thumb / 2 - 14)   // 左移到滑块旁、与其垂直居中对齐
            }
            Circle().fill(AppColor.primary).frame(width: thumb, height: thumb)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                .offset(y: y)
        }
        .frame(width: thumb, height: trackH)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { v in
                    zoomDragging = true
                    // 触点 y 反转归一化为 0…1：顶部=1(最大缩放)，底部=0；再驱动地图缩放
                    zoomLevel = min(1, max(0, 1 - Double(v.location.y) / trackH))
                    mapCtrl.setZoom(fraction: zoomLevel)
                }
                .onEnded { _ in zoomDragging = false }
        )
    }

    /// 定位键（单击循环：居中一次 → 跟随 → 关闭；跟随时高亮）
    private var locateButton: some View {
        Button { mapCtrl.cycleLocate() } label: {
            Image(systemName: mapCtrl.locateState == .off ? "location" : "location.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(mapCtrl.locateState == .following ? AppColor.primary : AppColor.ink)
                .frame(width: 44, height: 44)
                .background(Color.white).clipShape(Circle())
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        }
    }

    /// 悬浮圆形控件（可带下方小标签），filled 用于实心图标，active 高亮（如公里标开启）
    private func ctrl(_ icon: String, _ label: String? = nil, filled: Bool = false,
                      active: Bool = false, action: @escaping () -> Void = {}) -> some View {
        VStack(spacing: 3) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: filled ? .semibold : .regular))
                    .foregroundColor(active ? AppColor.primary : AppColor.ink)
                    .frame(width: 44, height: 44)
                    .background(Color.white).clipShape(Circle())
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            }
            if let label {
                Text(label).font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
            }
        }
    }

    private func cta(_ t: String, _ icon: String, _ bg: Color, _ fg: Color) -> some View {
        HStack { Image(systemName: icon); Text(t).fontWeight(.semibold) }
            .foregroundColor(fg).frame(maxWidth: .infinity).frame(height: 52).background(bg).cornerRadius(AppRadius.button)
    }
}

/// 一条叠加轨迹：id 用于增删与缓存键，name 供图例显示，coords 供地图绘制。
/// 在 overlayItems 中的下标即调色板颜色下标（图例与地图一致）。
private struct OverlayItem: Identifiable {
    let id: UUID
    let name: String
    let coords: [CLLocationCoordinate2D]
}

/// 叠加轨迹选择面板：多选已存轨迹，「完成」回调把选择应用到主地图。
/// selection 与主视图双向绑定（保留上次勾选）；onApply 在关闭前触发加载。
private struct OverlayPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Set<UUID>
    var onApply: () -> Void
    @State private var tracks: [Track] = []   // 列表数据，进入时一次性查库

    var body: some View {
        NavigationStack {
            List {
                if tracks.isEmpty {
                    Text("暂无已保存的轨迹").foregroundColor(AppColor.ink2)
                } else {
                    ForEach(tracks) { t in
                        Button { toggle(t.id) } label: {
                            HStack(spacing: 12) {
                                // 勾选态用实心对勾，未选用空心圈
                                Image(systemName: selection.contains(t.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selection.contains(t.id) ? AppColor.primary : AppColor.ink2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.name).foregroundColor(AppColor.ink)
                                    Text(String(format: "%.1f km", t.distance / 1000))
                                        .font(.caption).foregroundColor(AppColor.ink2)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("叠加轨迹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("清空") { selection.removeAll() } }
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { onApply(); dismiss() } }
            }
            .task { tracks = (try? TrackRepository().listTracks()) ?? [] }
        }
    }

    /// 勾选/取消某条轨迹。
    private func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }
}
