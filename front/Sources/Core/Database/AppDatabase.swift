import Foundation
import GRDB

/// GRDB 数据库容器与迁移（任务 1.1 / 1.3）。
final class AppDatabase {
    /// 全局单例：App 内所有仓储默认共用此连接（见 TrackRepository 默认参数）。
    static let shared = makeShared()

    /// GRDB 串行队列：所有读写都经它调度，保证线程安全。
    let dbQueue: DatabaseQueue

    /// 注入已建好的连接并立即跑迁移，确保拿到的库结构总是最新。
    init(_ dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try migrator.migrate(dbQueue)
    }

    /// 构造单例：在 Application Support 目录下打开/新建 hiking.sqlite。
    /// 失败直接 fatalError——库打不开属于不可恢复的启动级错误。
    private static func makeShared() -> AppDatabase {
        do {
            let folder = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let url = folder.appendingPathComponent("hiking.sqlite")
            let queue = try DatabaseQueue(path: url.path)
            return try AppDatabase(queue)
        } catch {
            fatalError("数据库初始化失败: \(error)")
        }
    }

    /// 迁移：每次结构变更新增一个 registerMigration，保证可平滑升级。
    private var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        #if DEBUG
        // 开发期结构一变就清库重建，省去手写中间迁移；正式包绝不能开（会丢用户数据）。
        m.eraseDatabaseOnSchemaChange = true
        #endif

        // v1：初始四张表——轨迹 / 轨迹点 / 航点 / 记录会话。
        m.registerMigration("v1_init") { db in
            try db.create(table: "track") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("source", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("isDeleted", .boolean).notNull().defaults(to: false)
                t.column("isSynced", .boolean).notNull().defaults(to: false)
                t.column("distance", .double).notNull().defaults(to: 0)
                t.column("movingTime", .double).notNull().defaults(to: 0)
                t.column("totalTime", .double).notNull().defaults(to: 0)
                t.column("ascent", .double).notNull().defaults(to: 0)
                t.column("descent", .double).notNull().defaults(to: 0)
                t.column("maxElevation", .double)
                t.column("minElevation", .double)
                t.column("pointCount", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "trackPoint") { t in
                t.autoIncrementedPrimaryKey("id")
                // 外键级联：删轨迹时自动删其所有点；trackId 加索引以加速按轨迹取点。
                t.column("trackId", .text).notNull().indexed()
                    .references("track", onDelete: .cascade)
                t.column("segment", .integer).notNull().defaults(to: 0)  // 断段编号（暂停/丢信号后新开一段）
                t.column("seq", .integer).notNull()                      // 段内序号，决定连线顺序
                t.column("lat", .double).notNull()
                t.column("lon", .double).notNull()
                t.column("elevation", .double)
                t.column("timestamp", .datetime)
                t.column("speed", .double)
                t.column("horizontalAccuracy", .double)
            }

            try db.create(table: "waypoint") { t in
                t.primaryKey("id", .text)
                t.column("trackId", .text).indexed()
                t.column("name", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("lat", .double).notNull()
                t.column("lon", .double).notNull()
                t.column("elevation", .double)
                t.column("note", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("isDeleted", .boolean).notNull().defaults(to: false)
                t.column("isSynced", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "recordingSession") { t in
                t.primaryKey("id", .text)
                t.column("state", .text).notNull()
                t.column("startedAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("distance", .double).notNull().defaults(to: 0)
                t.column("movingTime", .double).notNull().defaults(to: 0)
                t.column("ascent", .double).notNull().defaults(to: 0)
                t.column("descent", .double).notNull().defaults(to: 0)
                t.column("pointCount", .integer).notNull().defaults(to: 0)
            }
        }

        // v2：文件夹（轨迹分组）
        m.registerMigration("v2_folders") { db in
            try db.create(table: "folder") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("isDeleted", .boolean).notNull().defaults(to: false)
                t.column("isSynced", .boolean).notNull().defaults(to: false)
            }
            try db.alter(table: "track") { t in
                t.add(column: "folderId", .text)   // 关联 folder.id；nil = 未分组
            }
        }
        return m
    }
}
