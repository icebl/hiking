import Foundation
import GRDB

/// 轨迹仓储：增删改查 + 批量写点 + 列表（任务 1.4 / 1.5）。
/// 上层（记录/导入/详情等 ViewModel）唯一的持久化入口，屏蔽 GRDB 细节；
/// 删除统一走软删（isDeleted=true + isSynced=false），为三期云同步保留删除态。
struct TrackRepository {
    let db: AppDatabase
    // 默认复用全局单例连接；测试时可注入独立内存库。
    init(db: AppDatabase = .shared) { self.db = db }

    // 轨迹列表（未删除，按创建时间倒序）；search 非空时按名称过滤。
    func listTracks(search: String = "") throws -> [Track] {
        try db.dbQueue.read { dbx in
            var request = Track.filter(Column("isDeleted") == false)
            let q = search.trimmingCharacters(in: .whitespaces)
            if !q.isEmpty { request = request.filter(Column("name").like("%\(q)%")) }
            return try request.order(Column("createdAt").desc).fetchAll(dbx)
        }
    }

    // MARK: - 文件夹（任务2）

    func listFolders() throws -> [Folder] {
        try db.dbQueue.read { dbx in
            try Folder.filter(Column("isDeleted") == false)
                .order(Column("createdAt").desc).fetchAll(dbx)
        }
    }

    @discardableResult
    func createFolder(name: String) throws -> Folder {
        var f = Folder(name: name)
        try db.dbQueue.write { dbx in try f.save(dbx) }
        return f
    }

    func renameFolder(id: UUID, name: String) throws {
        _ = try db.dbQueue.write { dbx in
            try Folder.filter(key: id.uuidString)
                .updateAll(dbx, Column("name").set(to: name), Column("updatedAt").set(to: Date()))
        }
    }

    /// 删除文件夹（软删）并把其下轨迹移出（folderId 置 nil）。
    func deleteFolder(id: UUID) throws {
        try db.dbQueue.write { dbx in
            try Track.filter(Column("folderId") == id.uuidString)
                .updateAll(dbx, Column("folderId").set(to: nil), Column("updatedAt").set(to: Date()))
            try Folder.filter(key: id.uuidString)
                .updateAll(dbx, Column("isDeleted").set(to: true),
                           Column("isSynced").set(to: false), Column("updatedAt").set(to: Date()))
        }
    }

    /// 把轨迹移动到文件夹（folderId 为 nil = 移到未分组）。
    func moveTrack(id: UUID, to folderId: UUID?) throws {
        _ = try db.dbQueue.write { dbx in
            try Track.filter(key: id.uuidString)
                .updateAll(dbx, Column("folderId").set(to: folderId?.uuidString),
                           Column("isSynced").set(to: false), Column("updatedAt").set(to: Date()))
        }
    }

    func track(id: UUID) throws -> Track? {
        try db.dbQueue.read { try Track.fetchOne($0, key: id.uuidString) }
    }

    /// 保存轨迹并批量写入轨迹点（结算/导入共用）。
    /// 单事务内完成：先存轨迹行，再逐点/逐航点回填 trackId 后写入，保证整体原子性。
    func save(track: Track, points: [TrackPoint], waypoints: [Waypoint] = []) throws {
        try db.dbQueue.write { dbx in
            var t = track; t.updatedAt = Date()
            try t.save(dbx)
            // 强制改写 trackId，防止调用方传入的点/航点关联到错误轨迹。
            for var p in points { p.trackId = track.id; try p.insert(dbx) }
            for var w in waypoints { w.trackId = track.id; try w.save(dbx) }
        }
    }

    // MARK: - 记录中：增量落盘与会话（任务 3.8 崩溃恢复）

    /// 开始记录时建一条空轨迹行，供后续增量落点。
    func createInProgress(_ track: Track) throws {
        try db.dbQueue.write { dbx in var t = track; try t.save(dbx) }
    }

    /// 批量追加轨迹点（点须已带正确 trackId/segment/seq）。
    func appendPoints(_ points: [TrackPoint]) throws {
        guard !points.isEmpty else { return }
        try db.dbQueue.write { dbx in for var p in points { try p.insert(dbx) } }
    }

    /// 更新轨迹统计（记录中刷新 / 结算）。
    func updateStats(id: UUID, distance: Double, movingTime: Double, totalTime: Double,
                     ascent: Double, descent: Double, pointCount: Int) throws {
        _ = try db.dbQueue.write { dbx in
            try Track.filter(key: id.uuidString).updateAll(dbx,
                Column("distance").set(to: distance),
                Column("movingTime").set(to: movingTime),
                Column("totalTime").set(to: totalTime),
                Column("ascent").set(to: ascent),
                Column("descent").set(to: descent),
                Column("pointCount").set(to: pointCount),
                Column("updatedAt").set(to: Date()))
        }
    }

    func saveSession(_ session: RecordingSession) throws {
        try db.dbQueue.write { dbx in var s = session; s.updatedAt = Date(); try s.save(dbx) }
    }

    /// 未结束的记录会话（启动时检测崩溃恢复）。
    func activeSessions() throws -> [RecordingSession] {
        try db.dbQueue.read { try RecordingSession.fetchAll($0) }
    }

    func deleteSession(id: UUID) throws {
        _ = try db.dbQueue.write { dbx in try RecordingSession.filter(key: id.uuidString).deleteAll(dbx) }
    }

    /// 取某轨迹最后一个点（恢复时续 seq/segment）。
    func lastPoint(trackId: UUID) throws -> TrackPoint? {
        try db.dbQueue.read { dbx in
            try TrackPoint
                .filter(Column("trackId") == trackId.uuidString)
                .order(Column("segment").desc, Column("seq").desc)
                .fetchOne(dbx)
        }
    }

    /// 物理删除轨迹（级联删点，丢弃恢复用）。
    func hardDelete(id: UUID) throws {
        _ = try db.dbQueue.write { dbx in try Track.filter(key: id.uuidString).deleteAll(dbx) }
    }

    /// 取某轨迹全部点，按 段→序 升序，使连线顺序与采集顺序一致。
    func points(trackId: UUID) throws -> [TrackPoint] {
        try db.dbQueue.read { dbx in
            try TrackPoint
                .filter(Column("trackId") == trackId.uuidString)
                .order(Column("segment"), Column("seq"))
                .fetchAll(dbx)
        }
    }

    /// 取某轨迹未删除的航点，按创建时间升序（与打点先后一致）。
    func waypoints(trackId: UUID) throws -> [Waypoint] {
        try db.dbQueue.read { dbx in
            try Waypoint
                .filter(Column("trackId") == trackId.uuidString && Column("isDeleted") == false)
                .order(Column("createdAt"))
                .fetchAll(dbx)
        }
    }

    /// 新增单个航点（记录中打点）。
    func addWaypoint(_ w: Waypoint) throws {
        try db.dbQueue.write { dbx in var x = w; x.updatedAt = Date(); try x.save(dbx) }
    }

    /// 编辑航点名称/备注/类型（详情页标注点管理）。
    func updateWaypoint(id: UUID, name: String, note: String?, kind: WaypointKind) throws {
        _ = try db.dbQueue.write { dbx in
            try Waypoint.filter(key: id.uuidString).updateAll(dbx,
                Column("name").set(to: name),
                Column("note").set(to: note),
                Column("kind").set(to: kind.rawValue),
                Column("isSynced").set(to: false),
                Column("updatedAt").set(to: Date()))
        }
    }

    /// 软删除航点（保留同步删除状态，仿 softDelete）。
    func deleteWaypoint(id: UUID) throws {
        _ = try db.dbQueue.write { dbx in
            try Waypoint.filter(key: id.uuidString).updateAll(dbx,
                Column("isDeleted").set(to: true),
                Column("isSynced").set(to: false),
                Column("updatedAt").set(to: Date()))
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

    /// 本月累计（首页数据卡，任务 6.1）：返回（轨迹数, 总里程米, 总爬升米）。
    func monthlySummary() throws -> (count: Int, distance: Double, ascent: Double) {
        // TODO(6.1): 按当前月份聚合统计——当前为占位实现，实际统计的是全部轨迹而非本月。
        let tracks = try listTracks()
        return (tracks.count,
                tracks.reduce(0) { $0 + $1.distance },
                tracks.reduce(0) { $0 + $1.ascent })
    }
}
