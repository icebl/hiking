import Foundation
import CoreLocation
import Combine

/// 记录控制器（任务 3.5~3.10）：聚合定位/气压计，维护状态机、实时统计、增量落盘、崩溃恢复·续记。
final class RecordingController: ObservableObject {
    /// 记录状态机：idle 未开始 → recording 记录中 → paused 手动暂停。自动暂停不属于此状态（见 isAutoPaused）。
    enum State { case idle, recording, paused }

    @Published var state: State = .idle
    @Published var distance: Double = 0          // 累计水平距离，单位 m
    @Published var movingTime: TimeInterval = 0  // 运动用时（自动暂停时不累加）
    @Published var ascent: Double = 0            // 累计爬升，单位 m（去噪后）
    @Published var descent: Double = 0           // 累计下降，单位 m（去噪后）
    @Published var currentElevation: Double?     // 当前海拔，优先气压计相对值，否则 GPS 高度
    @Published var pointCount: Int = 0           // 已采集轨迹点总数
    @Published var isAutoPaused = false          // 静止自动暂停
    @Published var liveCoordinates: [CLLocationCoordinate2D] = []  // 记录中实时画线
    @Published var waypoints: [Waypoint] = []    // 本次记录已打标注点（记录页地图实时显示）
    @Published var waypointCount = 0             // 本次记录已打标注点数

    private let location = LocationManager.shared
    private let altimeter = AltimeterManager()
    private let repo = TrackRepository()
    private var cancellables = Set<AnyCancellable>()

    private var trackId: UUID?                   // 当前记录对应的轨迹 id（落盘/会话恢复都以此为键）
    private var session: RecordingSession?        // 崩溃恢复用的会话快照（随统计周期性写盘）
    private var startedAt = Date()                // 本次记录起始时间，用于总用时
    private var currentSegment = 0                // 当前段号；断段/续记时 +1（轨迹分段）
    private var currentSeq = 0                    // 全局递增序号，保证点的写入顺序
    private var lastLocation: CLLocation?         // 上一有效定位，用于计距与时间间隔判断
    private var lastEle: Double?                  // 上一去噪后海拔基准，用于爬升/下降累计
    private var lastMoveAt = Date()               // 上一次发生位移的时刻，用于静止自动暂停判定
    private var buffer: [TrackPoint] = []        // 增量落盘缓冲
    private var timer: Timer?                      // 1s 计时器：累计运动用时 + 自动暂停判定

    // 去噪/采样参数（任务 3.3 / 3.6）
    private let minAccuracy: CLLocationDistance = 30   // 精度差于此丢弃
    private var minMove: CLLocationDistance = 5        // 最小位移（设置页可改）
    private var autoPauseEnabled = true                // 静止自动暂停（设置页开关）
    private let ascentThreshold: Double = 5            // 爬升去噪 5m
    private let flushEvery = 10                        // 每 N 点落盘一次
    private let gapSeconds: TimeInterval = 60          // 间隔超此判为断段
    private let autoPauseSeconds: TimeInterval = 20    // 静止超此自动暂停

    // MARK: - 生命周期

    /// 全新开始记录。
    func start() {
        guard state == .idle else { return }
        startedAt = Date()
        currentSegment = 0; currentSeq = 0
        let track = Track(name: defaultName(), source: .recorded)
        trackId = track.id
        try? repo.createInProgress(track)
        let s = RecordingSession(id: track.id, state: .recording, startedAt: startedAt, updatedAt: startedAt,
                                 distance: 0, movingTime: 0, ascent: 0, descent: 0, pointCount: 0)
        session = s
        try? repo.saveSession(s)
        beginSensors()
    }

    /// 崩溃后续记：从持久化会话恢复统计与已记点，继续往同一条轨迹追加（从新段开始）。
    /// 参数 sessionId：待恢复的活动会话 id。前置条件 state==idle，否则忽略。
    func resume(sessionId: UUID) {
        guard state == .idle else { return }
        guard let s = (try? repo.activeSessions())?.first(where: { $0.id == sessionId }) else { return }
        session = s
        trackId = s.id
        startedAt = s.startedAt
        distance = s.distance; movingTime = s.movingTime
        ascent = s.ascent; descent = s.descent; pointCount = s.pointCount
        let pts = (try? repo.points(trackId: s.id)) ?? []
        liveCoordinates = pts.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        if let last = pts.last {
            currentSeq = last.seq + 1
            currentSegment = last.segment + 1     // 崩溃间隔 = 新段
            lastEle = last.elevation
        }
        lastLocation = nil                        // 不跨崩溃间隔计距离
        waypoints = (try? repo.waypoints(trackId: s.id)) ?? []   // 续记恢复已打点
        waypointCount = waypoints.count
        beginSensors()
    }

    /// 记录途中打点（快速选类型）：在最近有效定位处落一个航点，名称自动 = 类型+序号。
    /// 返回新建的航点（供拍照打点拿 id 关联照片）；无可用坐标（定位未就绪）返回 nil。
    @discardableResult
    func addWaypoint(kind: WaypointKind) -> Waypoint? {
        guard let id = trackId else { return nil }
        guard let c = lastLocation?.coordinate ?? liveCoordinates.last else { return nil }
        let w = Waypoint(id: UUID(), trackId: id, name: "\(kind.label)\(waypointCount + 1)",
                         kind: kind, lat: c.latitude, lon: c.longitude,
                         elevation: currentElevation, note: nil,
                         createdAt: Date(), updatedAt: Date(), isDeleted: false, isSynced: false)
        try? repo.addWaypoint(w)
        waypoints.append(w)              // 记录页地图实时显示
        waypointCount += 1
        return w
    }

    /// 手动暂停：停止累计用时与采点，写盘会话状态以便崩溃恢复。
    func pause() { state = .paused; persistSessionState() }
    /// 手动继续：复位 lastMoveAt 与自动暂停标志，避免恢复瞬间被误判为静止。
    func resume() { state = .recording; lastMoveAt = Date(); isAutoPaused = false; persistSessionState() }

    /// 结束 → 写入终值、删会话（任务 3.10）。
    func finish() throws -> Track {
        timer?.invalidate(); timer = nil
        location.stop(); altimeter.stop(); cancellables.removeAll()
        guard let id = trackId else { throw NSError(domain: "Recording", code: -1) }
        // 无任何采点：清理不入库
        guard pointCount > 0 else {
            try? repo.deleteSession(id: id); try? repo.hardDelete(id: id); reset()
            throw NSError(domain: "Recording", code: -3, userInfo: [NSLocalizedDescriptionKey: "未采集到轨迹点"])
        }
        flush()
        try repo.updateStats(id: id, distance: distance, movingTime: movingTime,
                             totalTime: Date().timeIntervalSince(startedAt),
                             ascent: ascent, descent: descent, pointCount: pointCount)
        try? repo.deleteSession(id: id)
        let track = try repo.track(id: id)
        reset()
        guard let track else { throw NSError(domain: "Recording", code: -2) }
        return track
    }

    /// 取消并丢弃在记轨迹（导航同时记录选“不保存”用）。
    func cancel() {
        timer?.invalidate(); timer = nil
        location.stop(); altimeter.stop(); cancellables.removeAll()
        if let id = trackId { try? repo.deleteSession(id: id); try? repo.hardDelete(id: id) }
        reset()
    }

    // MARK: - 崩溃恢复的非续记分支（启动弹窗用，无需活动传感器）

    /// 结束并保存：用已存点补算统计并写入，删会话。
    static func finalizeRecovered(_ session: RecordingSession) {
        let repo = TrackRepository()
        let pts = (try? repo.points(trackId: session.id)) ?? []
        let s = ImportService.statistics(of: pts)
        try? repo.updateStats(id: session.id, distance: s.distance, movingTime: session.movingTime,
                              totalTime: session.movingTime, ascent: s.ascent, descent: s.descent,
                              pointCount: pts.count)
        try? repo.deleteSession(id: session.id)
    }

    /// 丢弃：删轨迹（级联点）+ 删会话。
    static func discard(_ session: RecordingSession) {
        let repo = TrackRepository()
        try? repo.deleteSession(id: session.id)
        try? repo.hardDelete(id: session.id)
    }

    // MARK: - 内部

    /// 启动传感器：读取设置 → 视情况启气压计 → 订阅定位流 → 起计时器。start/resume 共用入口。
    private func beginSensors() {
        state = .recording
        lastMoveAt = Date()
        minMove = AppSettings.minMove                  // 读设置
        autoPauseEnabled = AppSettings.autoPause
        if AppSettings.useBarometer { altimeter.start() }  // 仅 GPS 时不启气压计
        location.start(background: true)
        location.$location.compactMap { $0 }.sink { [weak self] in self?.ingest($0) }.store(in: &cancellables)
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
    }

    /// 1s 计时：运动用时累加 + 静止自动暂停判定（任务 3.5 / 3.7）。
    private func tick() {
        guard state == .recording else { return }
        if autoPauseEnabled, Date().timeIntervalSince(lastMoveAt) > autoPauseSeconds { isAutoPaused = true }
        if !isAutoPaused { movingTime += 1 }
    }

    /// 处理一帧定位：精度过滤 → 断段/计距/海拔去噪 → 入缓冲 → 达阈落盘。记录主流程。
    private func ingest(_ loc: CLLocation) {
        guard state == .recording else { return }  // 暂停/自动暂停期间丢弃定位
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= minAccuracy else { return }  // 任务 3.6：精度差/无效丢弃

        var newSegment = false
        if let last = lastLocation {
            // 两点时间间隔过大判为断段（如锁屏后台被系统挂起），断段两端不连线、不计距
            let gap = loc.timestamp.timeIntervalSince(last.timestamp)
            if gap > gapSeconds {
                currentSegment += 1                 // 断段（任务 3.9，数据分段）
                newSegment = true
            } else {
                let d = loc.distance(from: last)
                guard d >= minMove else { return }    // 最小位移过滤：静止不记点
                distance += d
            }
            if !newSegment, let lastE = lastEle {     // 海拔去噪累计，跨段不计
                let e = loc.altitude
                if abs(e - lastE) >= ascentThreshold {
                    if e > lastE { ascent += e - lastE } else { descent += lastE - e }
                    lastEle = e
                }
            } else {
                lastEle = loc.altitude
            }
        } else {
            lastEle = loc.altitude
        }

        currentElevation = altimeter.relativeAltitude ?? loc.altitude  // 气压计相对高度优先，缺失退回 GPS 高度
        guard let id = trackId else { return }
        let p = TrackPoint(id: nil, trackId: id, segment: currentSegment, seq: currentSeq,
                           lat: loc.coordinate.latitude, lon: loc.coordinate.longitude,
                           elevation: loc.altitude, timestamp: loc.timestamp,
                           speed: loc.speed >= 0 ? loc.speed : nil,
                           horizontalAccuracy: loc.horizontalAccuracy)
        buffer.append(p)
        liveCoordinates.append(loc.coordinate)
        currentSeq += 1
        pointCount += 1
        lastLocation = loc
        lastMoveAt = Date()       // 有新点即视为移动，刷新静止计时
        isAutoPaused = false      // 收到有效位移则解除自动暂停

        if buffer.count >= flushEvery { flush() }  // 缓冲满即落盘，控制崩溃丢点上限
    }

    /// 落盘缓冲点 + 刷新轨迹统计与会话（崩溃不丢，任务 3.8）。
    private func flush() {
        guard let id = trackId else { return }
        if !buffer.isEmpty {
            let pts = buffer; buffer.removeAll()
            try? repo.appendPoints(pts)
        }
        try? repo.updateStats(id: id, distance: distance, movingTime: movingTime,
                              totalTime: Date().timeIntervalSince(startedAt),
                              ascent: ascent, descent: descent, pointCount: pointCount)
        if var s = session {
            s.state = (state == .paused) ? .paused : .recording
            s.distance = distance; s.movingTime = movingTime
            s.ascent = ascent; s.descent = descent; s.pointCount = pointCount
            session = s
            try? repo.saveSession(s)
        }
    }

    /// 仅写盘会话的状态字段（暂停/继续切换时用），不触碰统计与缓冲。
    private func persistSessionState() {
        guard var s = session else { return }
        s.state = (state == .paused) ? .paused : .recording
        session = s
        try? repo.saveSession(s)
    }

    /// 清空全部记录现场，回到 idle（finish/cancel 收尾后调用），供下次记录复用本实例。
    private func reset() {
        state = .idle; distance = 0; movingTime = 0; ascent = 0; descent = 0
        pointCount = 0; currentElevation = nil; isAutoPaused = false
        liveCoordinates = []; buffer = []; lastLocation = nil; lastEle = nil
        trackId = nil; session = nil; currentSegment = 0; currentSeq = 0
        waypointCount = 0; waypoints = []
    }

    private func defaultName() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date()) + " 徒步"
    }
}
