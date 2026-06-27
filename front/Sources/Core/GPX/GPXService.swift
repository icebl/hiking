import Foundation
import CoreGPX

/// GPX 导入/导出（任务 5.1 / 5.2 / 5.5）。MVP 仅 GPX 1.1，含 wpt。
struct GPXService {

    /// 解析后的中间结果：尚未落库，等上层结算成 Track。
    struct ParsedTrack {
        var name: String              // 轨迹显示名（缺失时由上层用文件名覆盖）
        var points: [TrackPoint]      // 轨迹点序列（按 seq 递增）
        var waypoints: [Waypoint]     // 文件内的航点（同一文件多轨迹共享同一份）
        var hasTime: Bool             // 是否含时间戳（决定能否算用时/速度）
        var hasElevation: Bool        // 是否含海拔（决定能否算爬升/剖面）
    }

    // parseFailed：文件无法解析；empty：解析成功但无有效轨迹点
    enum GPXError: Error { case parseFailed, empty }

    /// 解析 GPX 文件 → 内部模型（容错：缺 ele/time、多 trk 全导入）。
    func parse(url: URL) throws -> [ParsedTrack] {
        guard let gpx = GPXParser(withURL: url)?.parsedData() else { throw GPXError.parseFailed }

        let waypoints: [Waypoint] = gpx.waypoints.compactMap { wpt in
            guard let lat = wpt.latitude, let lon = wpt.longitude else { return nil }
            let kind = WaypointKind(rawValue: wpt.type ?? "") ?? .other   // 导入保留类型
            let w = Waypoint(id: UUID(), trackId: nil, name: wpt.name ?? "航点",
                             kind: kind, lat: lat, lon: lon, elevation: wpt.elevation,
                             note: wpt.desc, createdAt: Date(), updatedAt: Date(),
                             isDeleted: false, isSynced: false)
            return w
        }

        var result: [ParsedTrack] = []
        // 多条轨迹：MVP 不弹选择，全部导入（已定决策）
        for trk in gpx.tracks {
            var pts: [TrackPoint] = []
            var hasTime = false, hasEle = false
            var seq = 0   // 全段连续递增，跨 segment 不重置，保证点序唯一
            // segIdx 记录原始段号，用于导出时还原 <trkseg> 分段
            for (segIdx, seg) in trk.segments.enumerated() {
                for tp in seg.points {
                    guard let lat = tp.latitude, let lon = tp.longitude else { continue }   // 经纬度缺失则跳过该点
                    if tp.time != nil { hasTime = true }
                    if tp.elevation != nil { hasEle = true }
                    pts.append(TrackPoint(id: nil, trackId: UUID(), segment: segIdx, seq: seq,
                                          lat: lat, lon: lon, elevation: tp.elevation,
                                          timestamp: tp.time, speed: nil, horizontalAccuracy: nil))
                    seq += 1
                }
            }
            guard !pts.isEmpty else { continue }
            result.append(ParsedTrack(name: trk.name ?? "导入轨迹",
                                      points: pts, waypoints: waypoints,
                                      hasTime: hasTime, hasElevation: hasEle))
        }
        if result.isEmpty { throw GPXError.empty }
        // TODO(5.2): 缺海拔 → DEM 采样补；超大文件 → 分段解析进度
        return result
    }

    /// 导出为 GPX 1.1（含 wpt）。
    func export(track: Track, points: [TrackPoint], waypoints: [Waypoint]) throws -> URL {
        let root = GPXRoot(creator: "Hiking App")

        let gpxTrack = GPXTrack(); gpxTrack.name = track.name
        // 按 segment 分组，还原导入时记录的分段结构
        let grouped = Dictionary(grouping: points, by: { $0.segment })
        for seg in grouped.keys.sorted() {   // 段号升序，保证输出顺序稳定
            let s = GPXTrackSegment()
            for p in grouped[seg]!.sorted(by: { $0.seq < $1.seq }) {   // 段内按 seq 还原原始点序
                let tp = GPXTrackPoint(latitude: p.lat, longitude: p.lon)
                tp.elevation = p.elevation
                tp.time = p.timestamp
                s.add(trackpoint: tp)
            }
            gpxTrack.add(trackSegment: s)
        }
        root.add(track: gpxTrack)

        for w in waypoints {
            let wp = GPXWaypoint(latitude: w.lat, longitude: w.lon)
            wp.name = w.name; wp.elevation = w.elevation; wp.desc = w.note
            wp.type = w.kind.rawValue            // 导出保留类型（<type>）
            root.add(waypoint: wp)
        }

        // 写入临时目录：仅供分享面板读取，无需持久化
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(track.name).gpx")
        try root.gpx().write(to: tmp, atomically: true, encoding: .utf8)
        return tmp   // 交给系统分享面板（任务 5.5）
    }
}
