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
        self.distance = 0; self.movingTime = 0; self.totalTime = 0
        self.ascent = 0; self.descent = 0
        self.maxElevation = nil; self.minElevation = nil; self.pointCount = 0
    }
}

// MARK: - TrackPoint（轨迹点）
struct TrackPoint: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?              // 自增
    var trackId: UUID
    var segment: Int           // 分段号（断段用）
    var seq: Int               // 序号
    var lat: Double
    var lon: Double
    var elevation: Double?     // 海拔（气压计/GPS/DEM）
    var timestamp: Date?
    var speed: Double?         // m/s
    var horizontalAccuracy: Double?

    static let databaseTableName = "trackPoint"
    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Waypoint（航点/标注点）
enum WaypointKind: String, Codable {
    case camp, water, junction, danger, photo, other
}

struct Waypoint: Codable, Identifiable, Syncable, FetchableRecord, MutablePersistableRecord {
    var id: UUID
    var trackId: UUID?
    var name: String
    var kind: WaypointKind
    var lat: Double
    var lon: Double
    var elevation: Double?
    var note: String?
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var isSynced: Bool

    static let databaseTableName = "waypoint"
}

// MARK: - RecordingSession（进行中会话，用于崩溃恢复，对应任务 3.8）
enum RecordingState: String, Codable { case recording, paused }

struct RecordingSession: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    var id: UUID
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
