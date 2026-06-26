import SwiftUI
import CoreLocation

/// 框选区域下载离线影像（任务 2.7 / S2-B）：移动地图把目标装进中央取景框 → 选级别 → 预估 → 下载到本地 MBTiles。
struct OfflineDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var mapCtrl = MapController()
    @StateObject private var dl = OfflineDownloader()
    @State private var maxZoom = 16
    @State private var name = ""
    @State private var mapSize: CGSize = .zero

    private let marginX: CGFloat = 22
    private let frameTop: CGFloat = 100
    private let frameBottom: CGFloat = 300   // 给底部面板留位

    var body: some View {
        ZStack {
            MapLibreView(controller: mapCtrl).ignoresSafeArea()

            // 取景框
            GeometryReader { geo in
                let r = frameRect(geo.size)
                Rectangle()
                    .strokeBorder(AppColor.primary, lineWidth: 2)
                    .background(Color.primary.opacity(0.001))   // 不挡手势
                    .frame(width: r.width, height: r.height)
                    .position(x: r.midX, y: r.midY)
                    .onAppear { mapSize = geo.size }
            }
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer()
                panel
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .onDisappear { dl.cancel() }
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

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper("最高级别  z\(maxZoom)", value: $maxZoom, in: 12...16)

            if let reg = region() {
                let n = OfflineDownloader.tileCount(reg)
                Text(String(format: "约 %d 瓦片 · ~%.0f MB（z10–%d）", n, OfflineDownloader.estimateMB(reg), maxZoom))
                    .font(.subheadline).foregroundColor(AppColor.ink2)
                if n > 40000 {
                    Text("⚠ 范围/级别过大，建议缩小取景或降低级别").font(.caption).foregroundColor(AppColor.warning)
                }
            } else {
                Text("移动/缩放地图，把目标区域装进绿框").font(.subheadline).foregroundColor(AppColor.ink2)
            }

            if dl.phase == .downloading {
                ProgressView(value: Double(dl.done + dl.failed), total: Double(max(1, dl.total)))
                Text("\(dl.done)/\(dl.total)  失败 \(dl.failed)").font(.caption).foregroundColor(AppColor.ink2)
                Button { dl.cancel() } label: { btn("取消下载", AppColor.recording) }
            } else if dl.phase == .finished {
                Text("✅ 已完成：\(dl.done) 瓦片（失败 \(dl.failed)）").font(.subheadline).foregroundColor(AppColor.primary)
                Button { dismiss() } label: { btn("完成", AppColor.primary) }
            } else {
                TextField("离线包名字（如：本溪关门山）", text: $name)
                    .textFieldStyle(.roundedBorder)
                Button { startDownload() } label: { btn("开始下载", AppColor.primary) }
                    .disabled(region() == nil)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(12)
    }

    private func btn(_ t: String, _ c: Color) -> some View {
        Text(t).fontWeight(.semibold).foregroundColor(.white)
            .frame(maxWidth: .infinity).frame(height: 50).background(c).cornerRadius(AppRadius.button)
    }

    // MARK: - 计算
    private func frameRect(_ size: CGSize) -> CGRect {
        CGRect(x: marginX, y: frameTop,
               width: max(0, size.width - 2 * marginX),
               height: max(0, size.height - frameTop - frameBottom))
    }

    private func region() -> TileRegion? {
        guard let map = mapCtrl.mapView, mapSize != .zero, dl.phase != .downloading else { return nil }
        _ = mapCtrl.zoom    // 依赖 published zoom，使地图移动/缩放后重算
        let r = frameRect(mapSize)
        let nw = map.convert(CGPoint(x: r.minX, y: r.minY), toCoordinateFrom: map)
        let se = map.convert(CGPoint(x: r.maxX, y: r.maxY), toCoordinateFrom: map)
        guard nw.latitude != se.latitude else { return nil }
        return TileRegion(minLon: min(nw.longitude, se.longitude), minLat: min(nw.latitude, se.latitude),
                          maxLon: max(nw.longitude, se.longitude), maxLat: max(nw.latitude, se.latitude),
                          minZoom: 10, maxZoom: maxZoom)
    }

    private func startDownload() {
        guard let reg = region() else { return }
        let n = name.trimmingCharacters(in: .whitespaces)
        let base = n.isEmpty ? "影像-z\(maxZoom)" : n
        let dest = OfflineMaps.dir.appendingPathComponent("\(base).mbtiles")
        try? FileManager.default.removeItem(at: dest)
        dl.start(region: reg, dest: dest, name: base)
    }
}
