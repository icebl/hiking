import SwiftUI
import CoreLocation

/// 框选区域下载离线影像（任务 2.7 / S2-B，官方 MLNOfflineStorage）：
/// 移动地图把目标装进中央取景框 → 选级别 → 预估 → 下载并缓存 ESRI 卫星瓦片。
/// 下载后断网进到该区域，地图「在线影像」底图自动命中缓存渲染（无需切图层）。
struct OfflineDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var mapCtrl = MapController()          // 取景地图控制器（读当前可视范围）
    @StateObject private var pdl = OfflinePackDownloader()      // 下载器：发布 phase/进度供面板观察
    @State private var maxZoom = 16                            // 下载最高瓦片级别（12…16），越高越清晰也越大
    @State private var mapSize: CGSize = .zero                 // 地图视图尺寸，用于把绿框换算成地理范围
    @State private var box: CGRect = .zero                     // 选择框（屏幕坐标，点）；可拖四角自定义大小

    // 初始取景框相对屏幕的内边距（点）：左右各 marginX，上下分别留 frameTop/frameBottom
    private let marginX: CGFloat = 22
    private let frameTop: CGFloat = 100
    private let frameBottom: CGFloat = 300

    /// 选择框的上/下边，用于生成可拖拽手柄（仅调高度，宽度固定为全宽）。
    private enum Edge: CaseIterable { case top, bottom }

    var body: some View {
        ZStack {
            MapLibreView(controller: mapCtrl).ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    // 选择框：描边矩形本身不拦截手势（地图仍可平移/缩放定位）
                    Rectangle()
                        .strokeBorder(AppColor.primary, lineWidth: 2)
                        .frame(width: box.width, height: box.height)
                        .position(x: box.midX, y: box.midY)
                        .allowsHitTesting(false)
                    // 上/下边中点各一个拖拽手柄：仅调高度（宽度固定）
                    ForEach(Edge.allCases, id: \.self) { edge in
                        edgeHandle(edge, in: geo.size)
                    }
                }
                .onAppear {
                    mapSize = geo.size
                    if box == .zero { box = frameRect(geo.size) }   // 初始默认框
                }
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                panel
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white).padding(10).background(Color.black.opacity(0.5)).clipShape(Circle())
            }
            Spacer()
            Text("框选下载离线影像").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 6).background(Color.black.opacity(0.5)).cornerRadius(10)
            Spacer()
            Color.clear.frame(width: 40, height: 1)
        }
        .padding(.horizontal, 14).padding(.top, 8)
    }

    /// 底部面板：选级别 + 预估瓦片量/体积 + 按下载阶段切换的进度/结果/按钮。
    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper("最高级别  z\(maxZoom)", value: $maxZoom, in: 12...16)

            // 绿框对应区域有效时显示预估；否则提示先把目标装进框
            if let reg = region() {
                let n = OfflineDownloader.tileCount(reg)
                Text(String(format: "约 %d 瓦片 · ~%.0f MB（z10–%d）", n, OfflineDownloader.estimateMB(reg), maxZoom))
                    .font(.subheadline).foregroundColor(AppColor.ink2)
                if n > 40000 {   // 阈值保护：过大易超时/占空间，提示收窄
                    Text("⚠ 范围/级别过大，建议缩小取景或降低级别").font(.caption).foregroundColor(AppColor.warning)
                }
            } else {
                Text("移动/缩放地图定位，拖上/下边调整绿框高度").font(.subheadline).foregroundColor(AppColor.ink2)
            }

            // 按下载阶段呈现不同 UI：下载中(进度+取消) / 完成 / 失败(重试) / 空闲(开始)
            switch pdl.phase {
            case .downloading:
                ProgressView(value: Double(pdl.completed), total: Double(max(1, pdl.expected)))
                Text("已缓存 \(pdl.completed)/\(pdl.expected)").font(.caption).foregroundColor(AppColor.ink2)
                Button { pdl.cancel() } label: { btn("取消下载", AppColor.recording) }
            case .finished:
                Text("✅ 已缓存完成（\(pdl.completed) 项）。断网进到该区域，底图自动显示。")
                    .font(.subheadline).foregroundColor(AppColor.primary)
                Button { dismiss() } label: { btn("完成", AppColor.primary) }
            case .failed:
                Text("下载失败，请重试（确认已联网）。").font(.subheadline).foregroundColor(AppColor.warning)
                Button { startDownload() } label: { btn("重试", AppColor.primary) }.disabled(region() == nil)
            case .idle:
                Button { startDownload() } label: { btn("开始下载", AppColor.primary) }.disabled(region() == nil)
            }
        }
        .padding(16).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 18)).padding(12)
    }

    private func btn(_ t: String, _ c: Color) -> some View {
        Text(t).fontWeight(.semibold).foregroundColor(.white)
            .frame(maxWidth: .infinity).frame(height: 50).background(c).cornerRadius(AppRadius.button)
    }

    // MARK: - 选择框拖拽（仅调高度）
    /// 上/下边中点的拖拽手柄（横向药丸），拖动仅改对应边的 Y（高度），宽度不变。
    private func edgeHandle(_ edge: Edge, in size: CGSize) -> some View {
        let y = (edge == .top) ? box.minY : box.maxY
        return RoundedRectangle(cornerRadius: 5)
            .fill(Color.white)
            .frame(width: 46, height: 14)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(AppColor.primary, lineWidth: 2))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .position(x: box.midX, y: y)
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in resizeHeight(edge, to: v.location.y, in: size) })
    }

    /// 拖动上/下边调整高度：对应边跟随手指 Y、另一边固定；限制最小高度并夹在地图区域内。
    private func resizeHeight(_ edge: Edge, to yRaw: CGFloat, in size: CGSize) {
        let minH: CGFloat = 80
        let y = max(0, min(yRaw, size.height))
        var top = box.minY, bottom = box.maxY
        switch edge {
        case .top:    top = min(y, bottom - minH)
        case .bottom: bottom = max(y, top + minH)
        }
        box = CGRect(x: box.minX, y: top, width: box.width, height: bottom - top)
    }

    // MARK: - 计算
    /// 按内边距常量算出取景框在给定尺寸下的矩形（屏幕坐标，单位：点）。用于选择框的初始大小。
    private func frameRect(_ size: CGSize) -> CGRect {
        CGRect(x: marginX, y: frameTop,
               width: max(0, size.width - 2 * marginX),
               height: max(0, size.height - frameTop - frameBottom))
    }

    /// 把屏幕上的绿框换算成地理瓦片区域；下载中或尺寸未知时返回 nil（禁用下载）。
    private func region() -> TileRegion? {
        guard let map = mapCtrl.mapView, mapSize != .zero,
              box.width > 0, box.height > 0, pdl.phase != .downloading else { return nil }
        _ = mapCtrl.zoom    // 依赖 published zoom，地图移动/缩放后重算
        // 用户自定义的选择框（屏幕坐标）：左上/右下两屏幕点反投影为经纬度，作为区域对角
        let nw = map.convert(CGPoint(x: box.minX, y: box.minY), toCoordinateFrom: map)
        let se = map.convert(CGPoint(x: box.maxX, y: box.maxY), toCoordinateFrom: map)
        guard nw.latitude != se.latitude else { return nil }   // 退化（无高度）则视为无效
        // 用 min/max 规整成标准 bbox，固定从 z10 下到所选 maxZoom
        return TileRegion(minLon: min(nw.longitude, se.longitude), minLat: min(nw.latitude, se.latitude),
                          maxLon: max(nw.longitude, se.longitude), maxLat: max(nw.latitude, se.latitude),
                          minZoom: 10, maxZoom: maxZoom)
    }

    /// 以当前框选区域启动下载（区域无效则不做）。区域转 SW/NE 角坐标交给下载器。
    private func startDownload() {
        guard let reg = region() else { return }
        let name = "影像 z\(maxZoom)"
        pdl.start(sw: CLLocationCoordinate2D(latitude: reg.minLat, longitude: reg.minLon),
                  ne: CLLocationCoordinate2D(latitude: reg.maxLat, longitude: reg.maxLon),
                  minZoom: reg.minZoom, maxZoom: reg.maxZoom, name: name)
    }
}
