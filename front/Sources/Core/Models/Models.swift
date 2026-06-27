import Foundation
import GRDB

// MARK: - 同步预留协议（对应任务 1.3：为三期云同步预留）
/// 所有可同步实体共有的字段：稳定 UUID、时间戳、软删除、是否已同步。
protocol Syncable {
    var id: UUID { get }
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    var isDeleted: Bool { get set }   // 软删除
    var isSynced: Bool { get set }    // 三期上传云端后置 true
}

// MARK: - 轨迹来源
enum TrackSource: String, Codable {
    case recorded   // 本机记录
    case imported   // 导入
}

// MARK: - Track（轨迹）
struct Track: Codable, Identifiable, Syncable, FetchableRecord, MutablePersistableRecord {
    var id: UUID
    var name: String
    var source: TrackSource
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var isSynced: Bool

    var folderId: UUID?         // 所属文件夹（nil = 未分组）

    // 统计（结算后写入；导入时解析）
    var distance: Double        // 米
    var movingTime: Double      // 运动用时（秒）
    var totalTime: Double       // 全程用时（秒）
    var ascent: Double          // 累计爬升（米）
    var descent: Double         // 累计下降（米）
    var maxElevation: Double?
    var minElevation: Double?
    var pointCount: Int

    static let databaseTableName = "track"

    init(name: String, source: TrackSource) {
        self.id = UUID()
        self.name = name
        self.source = source
        let now = Date()
        self.createdAt = now; self.updatedAt = now
        self.isDeleted = false; self.isSynced = false
        self.folderId = nil
        self.distance = 0; self.movingTime = 0; self.totalTime = 0
        self.ascent = 0; self.descent = 0
        self.maxElevation = nil; self.minElevation = nil; self.pointCount = 0
    }
}

// MARK: - Folder（轨迹文件夹/分组）
struct Folder: Codable, Identifiable, Syncable, FetchableRecord, MutablePersistableRecord {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var isSynced: Bool

    static let databaseTableName = "folder"

    init(name: String) {
        self.id = UUID()
        self.name = name
        let now = Date()
        self.createdAt = now; self.updatedAt = now
        self.isDeleted = false; self.isSynced = false
    }
}

// MARK: - TrackPoint（轨迹点）
struct TrackPoint: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?              // 自增主键；插入前为 nil，didInsert 回填
    var trackId: UUID          // 所属轨迹（外键，删轨迹级联删点）
    var segment: Int           // 分段号（断段用：暂停/丢信号后 +1，段间不连线）
    var seq: Int               // 段内序号，决定同段内的连线顺序
    var lat: Double            // 纬度（度，WGS84）
    var lon: Double            // 经度（度，WGS84）
    var elevation: Double?     // 海拔（米，来源：气压计/GPS/DEM）
    var timestamp: Date?       // 采集时刻；用于算速度/用时
    var speed: Double?         // 瞬时速度（m/s）
    var horizontalAccuracy: Double?  // 水平精度（米），越小越准，可用于过滤漂移点

    static let databaseTableName = "trackPoint"
    // 插入成功后把数据库生成的自增 rowID 回填到 id。
    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Waypoint（航点/标注点）
/// 航点类型；展示样式（中文名/图标/颜色）见 WaypointStyle.swift 扩展。
enum WaypointKind: String, Codable {
    case camp, water, junction, danger, photo, other
}

struct Waypoint: Codable, Identifiable, Syncable, FetchableRecord, MutablePersistableRecord {
    var id: UUID
    var trackId: UUID?          // 所属轨迹；nil = 独立航点（不挂任何轨迹）
    var name: String
    var kind: WaypointKind
    var lat: Double             // 纬度（度，WGS84）
    var lon: Double             // 经度（度，WGS84）
    var elevation: Double?      // 海拔（米）
    var note: String?           // 备注
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var isSynced: Bool

    static let databaseTableName = "waypoint"
}

// MARK: - RecordingSession（进行中会话，用于崩溃恢复，对应任务 3.8）
/// 记录状态：进行中 / 已暂停。
enum RecordingState: String, Codable { case recording, paused }

/// 记录会话：每次开始记录写一条，结束/丢弃时删除。
/// 启动时若仍存在（见 activeSessions），说明上次异常退出，可据 id 续接对应轨迹恢复记录。
struct RecordingSession: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    var id: UUID               // 与对应轨迹共用同一 UUID，便于恢复时定位轨迹
    var state: RecordingState
    var startedAt: Date
    var updatedAt: Date
    // 统计快照（崩溃恢复后续用）
    var distance: Double
    var movingTime: Double
    var ascent: Double
    var descent: Double
    var pointCount: Int

    static let databaseTableName = "recordingSession"
}

// MARK: - UUID 存储策略
// GRDB 默认把 UUID 存为 16 字节 blob；本项目所有按 ID 的查询/更新都用 `uuidString`（文本，
// 如 filter(key: id.uuidString)、Column("trackId") == ...uuidString）。若不统一为文本编码，
// 文本≠blob 会导致按 ID 的更新/查询全部静默失败（移动轨迹无效、记录统计为 0、详情取不到点等）。
extension Track            { static var databaseUUIDEncodingStrategy: DatabaseUUIDEncodingStrategy { .uppercaseString } }
extension Folder           { static var databaseUUIDEncodingStrategy: DatabaseUUIDEncodingStrategy { .uppercaseString } }
extension TrackPoint       { static var databaseUUIDEncodingStrategy: DatabaseUUIDEncodingStrategy { .uppercaseString } }
extension Waypoint         { static var databaseUUIDEncodingStrategy: DatabaseUUIDEncodingStrategy { .uppercaseString } }
extension RecordingSession { static var databaseUUIDEncodingStrategy: DatabaseUUIDEncodingStrategy { .uppercaseString } }
