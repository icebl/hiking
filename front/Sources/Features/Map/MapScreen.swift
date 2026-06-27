import SwiftUI
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
    @State private var zoomLevel: Double = 0.5  // 缩放滑块位置（0…1），1=最大
    @State private var showKm = false           // 公里标开关
    @State private var showContours = false      // 等高线开关
    @State private var showRoadNetwork = false   // 路网开关（仅离线矢量底图有效）
    @State private var baseMode: MapBaseMode = .onlineRaster  // 当前底图：默认在线影像，可切离线矢量
    @State private var showLayerSheet = false                // 是否弹出底图选择对话框
    // 工具箱：测距 / 面积 / 距离雷达
    enum MeasureMode { case none, distance, area }           // 测量模式：无 / 测距(折线) / 面积(多边形)
    @State private var measure: MeasureMode = .none
    @State private var measurePoints: [CLLocationCoordinate2D] = []  // 测量时按点击顺序累积的坐标点
    @State private var showRadar = false                     // 距离雷达（以当前定位为中心的同心圈）开关
    @State private var showToolSheet = false                 // 是否弹出工具箱对话框

    var body: some View {
        ZStack {
            // 底图视图：把上面各开关/状态下传给原生地图渲染
            MapLibreView(controller: mapCtrl, baseMode: baseMode, showKmMarkers: showKm,
                         showContours: showContours, contourPath: OfflineMaps.contourPack()?.path,
                         measureCoordinates: measurePoints, measureIsArea: measure == .area, showRadar: showRadar,
                         showRoadNetwork: showRoadNetwork,
                         onTap: { c in
                             // 测量进行中：点击落点累积进折线/多边形；否则只读取经纬度显示
                             if measure != .none { measurePoints.append(c) }
                             else { tapped = CoordFormatter.string(c, format: AppSettings.coordFormat) }
                         })
                .ignoresSafeArea()

            // 信息条：靠上居中（WGS84 浅绿高亮）+ 缩放级别读数（诊断）
            VStack(spacing: 6) {
                infoBar
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
                    ctrl("square.on.square", "叠加")          // TODO: 多轨迹叠加面板
                    ctrl("wrench.and.screwdriver", "工具", active: measure != .none || showRadar) { showToolSheet = true }
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
                        + Text(" · 海拔 未知").foregroundColor(.white)
                        Spacer()
                        Button { self.tapped = nil } label: {
                            Image(systemName: "xmark").foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .font(.caption)
                    .padding(.vertical, 10).padding(.horizontal, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.72))
                }
                .padding(.bottom, 96)
            }

            // 底部：测量条（测距/面积时）+ 记录 / 导航
            VStack {
                Spacer()
                if measure != .none { measureBar.padding(.horizontal, 16).padding(.bottom, 8) }
                HStack(spacing: 12) {
                    Button { showRecording = true } label: { cta("记录", "record.circle", .white, AppColor.ink) }
                    // 导航按钮暂时隐藏（功能保留，待 4.5 选轨迹进入导航后再开放）
                    if false {
                        Button { /* TODO(4.5): 选轨迹进入导航 */ } label: { cta("导航", "location.north.line.fill", AppColor.primary, .white) }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 30)
            }
        }
        .fullScreenCover(isPresented: $showRecording) { RecordingView() }
        // 进入主地图即前台定位（驱动信息条实时经纬度/海拔）；离开页面停止以省电。
        // 注：记录/导航页各自管理后台定位，互不影响（最后一次 start 的配置生效）。
        .onAppear { loc.requestWhenInUse(); loc.start(background: false) }
        .onDisappear { loc.stop() }
        // 工具箱对话框：切换测量模式都会清空已有点并关闭经纬度读数，避免状态串扰
        .confirmationDialog("工具箱", isPresented: $showToolSheet, titleVisibility: .visible) {
            Button("测距") { measure = .distance; measurePoints = []; tapped = nil }
            Button("面积") { measure = .area; measurePoints = []; tapped = nil }
            Button(showRadar ? "关闭距离雷达" : "距离雷达") { showRadar.toggle() }
            if measure != .none { Button("退出测量", role: .destructive) { measure = .none; measurePoints = [] } }
            Button("取消", role: .cancel) {}
        } message: { Text("点击地图连点测量；距离雷达以当前定位为中心显示同心圈") }
        // 底图选择对话框：固定一项在线影像 + 动态列出本地已导入的矢量包
        .confirmationDialog("选择底图", isPresented: $showLayerSheet, titleVisibility: .visible) {
            Button("在线影像（ESRI，含已缓存离线区域）") { baseMode = .onlineRaster }
            ForEach(OfflineMaps.list().filter { OfflineMaps.isVectorBase($0) }, id: \.self) { url in
                Button("离线矢量 · \(url.deletingPathExtension().lastPathComponent)") {
                    baseMode = .offlineVector(path: url.path)   // 切到该矢量包作为底图
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("卫星离线：在「在线影像」底图下，已框选下载的区域断网自动显示")
        }
    }

    // MARK: - 子组件

    /// 当前是否为离线矢量底图（路网/标注仅此模式有效）。
    private var isVectorBase: Bool {
        if case .offlineVector = baseMode { return true }
        return false
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
        .background(Color.black.opacity(0.78)).cornerRadius(12)
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
            .font(.system(size: 11.5, weight: .medium))
            .padding(.vertical, 6).padding(.horizontal, 14)
            .background(Color.black.opacity(0.72)).cornerRadius(12)
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
    private var zoomSlider: some View {
        ZStack(alignment: .top) {
            Capsule().fill(Color.white.opacity(0.6)).frame(width: 4, height: 110)
            ZStack {
                Circle().fill(AppColor.primary).frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                Text(String(format: "%.0f", mapCtrl.zoom))
                    .font(.system(size: 11, weight: .bold)).foregroundColor(.white)
            }
            .offset(y: CGFloat(1 - zoomLevel) * 83)   // zoomLevel=1 时圆点在顶端，越大越上
        }
        .frame(width: 30, height: 113)
        .contentShape(Rectangle())
        .gesture(
            DragGesture().onChanged { v in
                // 触点 y 反转归一化为 0…1：顶部=1(最大缩放)，底部=0；再驱动地图缩放
                let frac = 1 - Double(v.location.y) / 113
                zoomLevel = min(1, max(0, frac))
                mapCtrl.setZoom(fraction: zoomLevel)
            }
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
