import Foundation

/// 轨迹编辑（裁剪/拆分/反向/合并）：均「另存为新轨迹」，原轨迹保留不动。
/// 复用 ImportService.statistics 重算统计、TrackRepository.save 入库。
enum TrackEditor {
    private static var repo: TrackRepository { TrackRepository() }

    /// 用给定点新建一条轨迹：清掉旧点的主键(重新入库)、重排全局 seq、按几何重算统计。
    @discardableResult
    static func save(name: String, points raw: [TrackPoint], source: TrackSource) throws -> Track {
        guard raw.count > 1 else { throw NSError(domain: "TrackEditor", code: -1,
                                                 userInfo: [NSLocalizedDescriptionKey: "点数不足，无法生成轨迹"]) }
        var pts = raw
        for i in pts.indices {
            pts[i].id = nil          // 置空主键 → 作为新行插入（否则会与原轨迹的点主键冲突）
            pts[i].seq = i           // 重排连续序号（segment 保留，决定分段连线）
        }
        var t = Track(name: name, source: source)
        let s = ImportService.statistics(of: pts)
        t.distance = s.distance; t.ascent = s.ascent; t.descent = s.descent
        t.maxElevation = s.maxEle; t.minElevation = s.minEle; t.pointCount = pts.count
        try repo.save(track: t, points: pts, waypoints: [])
        return t
    }

    /// 反向另存：点序倒置，存为「原名 反向」。
    @discardableResult
    static func reverseSave(_ trackId: UUID) throws -> Track? {
        guard let t = try repo.track(id: trackId) else { return nil }
        let pts = try repo.points(trackId: trackId)
        guard pts.count > 1 else { return nil }
        return try save(name: t.name + " 反向", points: Array(pts.reversed()), source: t.source)
    }

    /// 按段拆分：每个 segment 存为一条新轨迹。返回拆出的条数（单段返回 0=不拆）。
    @discardableResult
    static func splitBySegment(_ trackId: UUID) throws -> Int {
        guard let t = try repo.track(id: trackId) else { return 0 }
        let pts = try repo.points(trackId: trackId)
        let groups = Dictionary(grouping: pts, by: { $0.segment })
        let keys = groups.keys.sorted()
        guard keys.count > 1 else { return 0 }
        for (i, k) in keys.enumerated() {
            let seg = groups[k]!.sorted { $0.seq < $1.seq }
            if seg.count > 1 { _ = try save(name: t.name + " 段\(i + 1)", points: seg, source: t.source) }
        }
        return keys.count
    }

    /// 合并多条：按给定顺序首尾相接，每条源轨迹各占一个 segment（避免跨条连线），存为新轨迹。
    @discardableResult
    static func merge(_ trackIds: [UUID]) throws -> Track? {
        guard trackIds.count >= 2 else { return nil }
        var all: [TrackPoint] = []
        for (i, id) in trackIds.enumerated() {
            var pts = try repo.points(trackId: id)
            for j in pts.indices { pts[j].segment = i }   // 每条源轨迹独立成段
            all.append(contentsOf: pts)
        }
        return try save(name: "合并轨迹", points: all, source: .imported)
    }

    /// 裁剪首尾：保留 [from, to] 闭区间的点，存为「原名 裁剪」。
    @discardableResult
    static func trimSave(_ trackId: UUID, from: Int, to: Int) throws -> Track? {
        guard let t = try repo.track(id: trackId) else { return nil }
        let pts = try repo.points(trackId: trackId)
        guard from >= 0, to < pts.count, from < to else { return nil }
        return try save(name: t.name + " 裁剪", points: Array(pts[from...to]), source: t.source)
    }

    /// 平滑去噪另存：对 GPS 抖动/海拔毛刺滤波（见 TrackSmoother）后存为「原名 平滑」，原轨迹保留。
    /// 统计由 save → ImportService.statistics 在平滑后的点上重算，里程/爬升更贴近真实。
    @discardableResult
    static func smoothSave(_ trackId: UUID) throws -> Track? {
        guard let t = try repo.track(id: trackId) else { return nil }
        let pts = try repo.points(trackId: trackId)
        guard pts.count > 2 else { return nil }   // 点太少无意义
        return try save(name: t.name + " 平滑", points: TrackSmoother.smooth(pts), source: t.source)
    }
}
