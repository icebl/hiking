import SwiftUI
import UIKit
import CoreLocation

/// 轨迹缩略图（任务 6.2，参照 UI/U3）：把轨迹形状离线绘制成方形封面图，列表行/详情页当封面。
/// 渲染结果按 trackId + 点数 + 边长(px) 缓存到 Caches/track-thumbs/，避免重复绘制；点数变化即换文件自动失效。
enum TrackThumbnail {

    /// 缓存目录（首次访问时创建）。放 Caches，系统空间紧张时可回收，丢失会自动重绘。
    private static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("track-thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// 缓存文件名带 pointCount：轨迹点数变化（续记/编辑）即指向新文件，旧图自然失效。
    private static func cacheURL(_ trackId: UUID, _ pointCount: Int, _ side: Int) -> URL {
        dir.appendingPathComponent("\(trackId.uuidString)-\(pointCount)-\(side).png")
    }

    /// 读磁盘缓存；命中返回图，未命中返回 nil。
    static func cached(_ trackId: UUID, _ pointCount: Int, side: Int) -> UIImage? {
        UIImage(contentsOfFile: cacheURL(trackId, pointCount, side).path)
    }

    /// 渲染并写缓存（后台线程调用）；点数 <2 无法成线返回 nil。
    static func render(coords: [CLLocationCoordinate2D], trackId: UUID, pointCount: Int, side: Int) -> UIImage? {
        guard coords.count > 1 else { return nil }
        let img = draw(coords: coords, side: side)
        if let data = img.pngData() { try? data.write(to: cacheURL(trackId, pointCount, side)) }
        return img
    }

    /// 纯绘制：等距投影 → 等比适配到方图（留白）→ 描红色折线 + 起点绿点。不读写缓存。
    static func draw(coords: [CLLocationCoordinate2D], side: Int) -> UIImage {
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            // 浅色地图底
            UIColor(red: 0.92, green: 0.93, blue: 0.90, alpha: 1).setFill()
            c.fill(CGRect(origin: .zero, size: size))
            guard coords.count > 1 else { return }

            // 等距投影：经度按平均纬度的 cos 收缩，避免高纬度横向拉伸；纬度直接用
            let meanLat = coords.map { $0.latitude }.reduce(0, +) / Double(coords.count)
            let k = cos(meanLat * .pi / 180)
            let xs = coords.map { $0.longitude * k }
            let ys = coords.map { $0.latitude }
            let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
            let spanX = max(maxX - minX, 1e-9), spanY = max(maxY - minY, 1e-9)  // 防退化除零

            // 等比缩放 + 居中，四周留 14% 白边
            let pad = CGFloat(side) * 0.14
            let avail = CGFloat(side) - pad * 2
            let scale = min(avail / CGFloat(spanX), avail / CGFloat(spanY))
            let drawW = CGFloat(spanX) * scale, drawH = CGFloat(spanY) * scale
            let offX = (CGFloat(side) - drawW) / 2, offY = (CGFloat(side) - drawH) / 2
            func pt(_ i: Int) -> CGPoint {
                let x = offX + CGFloat(xs[i] - minX) * scale
                let y = CGFloat(side) - (offY + CGFloat(ys[i] - minY) * scale)  // y 翻转：北在上
                return CGPoint(x: x, y: y)
            }

            // 轨迹折线（红，圆角端点）
            let path = UIBezierPath()
            path.move(to: pt(0))
            for i in 1..<coords.count { path.addLine(to: pt(i)) }
            c.setLineCap(.round); c.setLineJoin(.round)
            UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1).setStroke()
            path.lineWidth = max(2, CGFloat(side) / 28)
            path.stroke()

            // 起点绿点
            let r = max(2.5, CGFloat(side) / 22)
            UIColor(red: 0.12, green: 0.62, blue: 0.33, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: pt(0).x - r, y: pt(0).y - r, width: r * 2, height: r * 2))
        }
    }
}

/// 轨迹缩略图视图：先读磁盘缓存命中即显示；未命中则后台加载轨迹点(下采样)渲染，完成后填入。
/// 加载期间显示占位图标，避免列表滚动卡顿（重活全在 detached 任务里）。
struct TrackThumbnailView: View {
    let trackId: UUID
    let pointCount: Int          // 用于缓存键：点数变化触发重绘
    var side: CGFloat = 52
    var corner: CGFloat = 8
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner).fill(Color(hex: 0xEAEDE6))
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.system(size: side * 0.34)).foregroundColor(AppColor.divider)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .task(id: trackId) { await load() }   // 行复用/换轨迹时重载
    }

    /// 命中缓存直接用；否则后台查点→下采样→渲染→写缓存，再回主线程显示。
    private func load() async {
        let px = Int(side * UIScreen.main.scale)
        if let cached = TrackThumbnail.cached(trackId, pointCount, side: px) { image = cached; return }
        let id = trackId, pc = pointCount
        let img = await Task.detached(priority: .utility) { () -> UIImage? in
            let pts = (try? TrackRepository().points(trackId: id)) ?? []
            guard pts.count > 1 else { return nil }
            // 下采样到约 300 点，绘制足够且省时
            let step = max(1, pts.count / 300)
            var coords: [CLLocationCoordinate2D] = []
            var i = 0
            while i < pts.count {
                coords.append(CLLocationCoordinate2D(latitude: pts[i].lat, longitude: pts[i].lon))
                i += step
            }
            return TrackThumbnail.render(coords: coords, trackId: id, pointCount: pc, side: px)
        }.value
        if let img { image = img }
    }
}
