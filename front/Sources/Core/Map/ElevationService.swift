import Foundation
import UIKit

/// 高程查询（DEM 补海拔，任务 C）：用公开的 Terrarium terrain-RGB 高程瓦片按经纬度取点高程。
/// 解码公式：elevation = (R*256 + G + B/256) − 32768（米）。瓦片解码后缓存，避免重复下载/解码。
/// 需联网；离线高程（纳入下载区域）为后续增强。
final class ElevationService {
    static let shared = ElevationService()
    private init() {}

    private let zoom = 12                    // 约 38m/像素，匹配 ~30m DEM，覆盖/体积均衡
    private let tileSize = 256
    private let session = URLSession.shared
    private let cache = NSCache<NSString, NSData>()   // key="z/x/y" → 解码后的 RGBA8 像素缓冲

    /// AWS 开放高程瓦片（Terrarium 编码，免 key）。
    private func tileURL(z: Int, x: Int, y: Int) -> URL {
        URL(string: "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/\(z)/\(x)/\(y).png")!
    }

    /// 取某经纬度的海拔（米）；网络/解码失败返回 nil。
    func elevation(lat: Double, lon: Double) async -> Double? {
        let n = Double(1 << zoom)
        let latR = lat * .pi / 180
        let xf = (lon + 180) / 360 * n
        let yf = (1 - log(tan(latR) + 1 / cos(latR)) / .pi) / 2 * n   // Web Mercator Y
        guard xf.isFinite, yf.isFinite else { return nil }
        let x = Int(xf), y = Int(yf)
        guard let buf = await tileBuffer(z: zoom, x: x, y: y) else { return nil }
        // 瓦片内像素坐标（夹到边界内）
        let px = min(tileSize - 1, max(0, Int((xf - Double(x)) * Double(tileSize))))
        let py = min(tileSize - 1, max(0, Int((yf - Double(y)) * Double(tileSize))))
        let i = (py * tileSize + px) * 4
        guard i + 2 < buf.count else { return nil }
        let r = Double(buf[i]), g = Double(buf[i + 1]), b = Double(buf[i + 2])
        return (r * 256 + g + b / 256) - 32768
    }

    /// 批量补海拔：把 elevation 为 nil 的点用 DEM 填上（瓦片缓存→实际只下少量唯一瓦片）。
    func fillElevations(_ points: [TrackPoint]) async -> [TrackPoint] {
        var out = points
        for i in out.indices where out[i].elevation == nil {
            if let e = await elevation(lat: out[i].lat, lon: out[i].lon) { out[i].elevation = e }
        }
        return out
    }

    /// 取瓦片的 RGBA8 像素缓冲（命中缓存直接返回，否则下载+解码并缓存）。
    private func tileBuffer(z: Int, x: Int, y: Int) async -> [UInt8]? {
        let key = "\(z)/\(x)/\(y)" as NSString
        if let cached = cache.object(forKey: key) { return [UInt8](cached as Data) }
        guard let (data, _) = try? await session.data(from: tileURL(z: z, x: x, y: y)),
              let cg = UIImage(data: data)?.cgImage else { return nil }
        let w = tileSize, h = tileSize
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))   // 重绘为已知 RGBA8 布局再读像素
        cache.setObject(Data(buf) as NSData, forKey: key)
        return buf
    }
}
