import Foundation
import CoreLocation

/// 导入分派与入库（任务 5.x）：按扩展名选择 GPX / KML 解析，并把解析结果结算成 Track 落库。
enum ImportService {

    enum ImportError: LocalizedError {
        case unsupported(String)
        var errorDescription: String? {
            switch self {
            case .unsupported(let ext): return "暂不支持的文件类型：.\(ext)（目前支持 GPX、KML；KMZ 待后续）"
            }
        }
    }

    /// 解析文件（自动按扩展名分派）。返回多条轨迹（多 trk/Placemark 全导入）。
    /// 显示名统一用文件名（用户在微信/文件里看到的名字，确保可识别回显）；多条加序号。
    static func parse(url: URL) throws -> [GPXService.ParsedTrack] {
        var tracks: [GPXService.ParsedTrack]
        switch url.pathExtension.lowercased() {
        case "gpx": tracks = try GPXService().parse(url: url)
        case "kml": tracks = try KMLService().parse(url: url)
        default:    throw ImportError.unsupported(url.pathExtension.lowercased())
        }
        let base = url.deletingPathExtension().lastPathComponent   // 去扩展名的文件名
        if !base.isEmpty {
            for i in tracks.indices {
                // 单条直接用文件名；多条加 (1)(2)… 序号避免重名
                tracks[i].name = tracks.count > 1 ? "\(base) (\(i + 1))" : base
            }
        }
        return tracks
    }

    /// 缺海拔的轨迹用在线 DEM 补海拔；已有海拔则原样返回。返回补好的 ParsedTrack（统计在 save 时按补后点重算）。
    static func fillingElevationIfNeeded(_ parsed: GPXService.ParsedTrack) async -> GPXService.ParsedTrack {
        guard !parsed.hasElevation else { return parsed }
        var t = parsed
        t.points = await ElevationService.shared.fillElevations(parsed.points)
        t.hasElevation = t.points.contains { $0.elevation != nil }
        return t
    }

    /// 把一条解析结果结算为 Track（计算距离/爬升/海拔区间）并写入数据库。
    @discardableResult
    static func save(_ parsed: GPXService.ParsedTrack) throws -> Track {
        var track = Track(name: parsed.name, source: .imported)
        let stats = statistics(of: parsed.points)
        track.distance = stats.distance
        track.ascent = stats.ascent
        track.descent = stats.descent
        track.maxElevation = stats.maxEle
        track.minElevation = stats.minEle
        track.pointCount = parsed.points.count
        try TrackRepository().save(track: track, points: parsed.points, waypoints: parsed.waypoints)
        return track
    }

    /// 距离/爬升统计（导入文件无实时数据，按几何计算；爬升去噪阈值 5m）。
    /// 返回：总距离(米)、累计爬升(米)、累计下降(米)、最高/最低海拔(米，无海拔时为 nil)。
    static func statistics(of points: [TrackPoint])
        -> (distance: Double, ascent: Double, descent: Double, maxEle: Double?, minEle: Double?) {
        guard points.count > 1 else { return (0, 0, 0, points.first?.elevation, points.first?.elevation) }
        var distance = 0.0, ascent = 0.0, descent = 0.0
        var maxEle = -Double.greatestFiniteMagnitude, minEle = Double.greatestFiniteMagnitude
        var hasEle = false               // 全程是否出现过海拔，决定 max/min 是否有效
        var lastEle: Double?             // 上一个「确认」的海拔基准点（去噪后）
        var prev: CLLocation?            // 上一个有效坐标，用于累加段距离
        let ascentThreshold = 5.0        // 爬升去噪阈值：高度差 <5m 视为噪声不计

        for p in points {
            let loc = CLLocation(latitude: p.lat, longitude: p.lon)
            if let prev { distance += loc.distance(from: prev) }   // 相邻点大圆距离累加
            prev = loc
            if let e = p.elevation {
                hasEle = true
                maxEle = max(maxEle, e); minEle = min(minEle, e)   // 极值用原始海拔，不受阈值影响
                // 仅当与基准点高差超阈值才计入爬升/下降，并把基准前移到当前点
                if let le = lastEle, abs(e - le) >= ascentThreshold {
                    if e > le { ascent += e - le } else { descent += le - e }
                    lastEle = e
                } else if lastEle == nil {
                    lastEle = e   // 首个海拔点：仅设基准，不计爬升
                }
            }
        }
        return (distance, ascent, descent, hasEle ? maxEle : nil, hasEle ? minEle : nil)
    }
}
