import Foundation
import GRDB

/// 轨迹仓储：增删改查 + 批量写点 + 列表（任务 1.4 / 1.5）。
struct TrackRepository {
    let db: AppDatabase
    init(db: AppDatabase = .shared) { self.db = db }

    // 轨迹列表（未删除，按创建时间倒序）
    func listTracks() throws -> [Track] {
        try db.dbQueue.read { dbx in
            try Track
                .filter(Column("isDeleted") == false)
                .order(Column("createdAt").desc)
                .fetchAll(dbx)
        }
    }

    func track(id: UUID) throws -> Track? {
        try db.dbQueue.read { try Track.fetchOne($0, key: id.uuidString) }
    }

    /// 保存轨迹并批量写入轨迹点（结算/导入共用）。
    func save(track: Track, points: [TrackPoint], waypoints: [Waypoint] = []) throws {
        try db.dbQueue.write { dbx in
            var t = track; t.updatedAt = Date()
            try t.save(dbx)
            for var p in points { p.trackId = track.id; try p.insert(dbx) }
            for var w in waypoints { w.trackId = track.id; try w.save(dbx) }
        }
    }

    func points(trackId: UUID) throws -> [TrackPoint] {
        try db.dbQueue.read { dbx in
            try TrackPoint
                .filter(Column("trackId") == trackId.uuidString)
                .order(Column("segment"), Column("seq"))
                .fetchAll(dbx)
        }
    }

    func waypoints(trackId: UUID) throws -> [Waypoint] {
        try db.dbQueue.read { dbx in
            try Waypoint
                .filter(Column("trackId") == trackId.uuidString && Column("isDeleted") == false)
                .fetchAll(dbx)
        }
    }

    func rename(id: UUID, name: String) throws {
        _ = try db.dbQueue.write { dbx in
            try Track.filter(key: id.uuidString)
                .updateAll(dbx, Column("name").set(to: name), Column("updatedAt").set(to: Date()))
        }
    }

    /// 软删除（保留以便三期同步删除状态）。
    func softDelete(id: UUID) throws {
        _ = try db.dbQueue.write { dbx in
            try Track.filter(key: id.uuidString)
                .updateAll(dbx,
                           Column("isDeleted").set(to: true),
                           Column("isSynced").set(to: false),
                           Column("updatedAt").set(to: Date()))
        }
    }

    // 本月累计（首页数据卡，任务 6.1）
    func monthlySummary() throws -> (count: Int, distance: Double, ascent: Double) {
        // TODO(6.1): 按当前月份聚合统计
        let tracks = try listTracks()
        return (tracks.count,
                tracks.reduce(0) { $0 + $1.distance },
                tracks.reduce(0) { $0 + $1.ascent })
    }
}
