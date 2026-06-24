import Foundation
import CoreLocation
import Combine

/// 记录控制器（任务 3.5~3.10）：聚合定位/气压计，维护状态机、实时统计、增量落盘。
final class RecordingController: ObservableObject {
    enum State { case idle, recording, paused }

    @Published var state: State = .idle
    @Published var distance: Double = 0       // m
    @Published var movingTime: TimeInterval = 0
    @Published var ascent: Double = 0
    @Published var descent: Double = 0
    @Published var currentElevation: Double?
    @Published var pointCount: Int = 0

    private let location = LocationManager.shared
    private let altimeter = AltimeterManager()
    private var cancellables = Set<AnyCancellable>()
    private var session: RecordingSession?
    private var lastLocation: CLLocation?
    private var buffer: [TrackPoint] = []      // 增量落盘缓冲

    // 去噪/采样参数（任务 3.3 / 3.6）
    private let minAccuracy: CLLocationDistance = 30   // 精度差于此丢弃
    private let minMove: CLLocationDistance = 5        // 最小位移 5m
    private let ascentThreshold: Double = 5            // 爬升去噪 5m

    func start() {
        guard state == .idle else { return }
        session = RecordingSession(id: UUID(), state: .recording, startedAt: Date(), updatedAt: Date(),
                                   distance: 0, movingTime: 0, ascent: 0, descent: 0, pointCount: 0)
        // TODO(3.8): 持久化 session 以便崩溃恢复
        state = .recording
        altimeter.start()
        location.start(background: true)
        location.$location.compactMap { $0 }.sink { [weak self] in self?.ingest($0) }.store(in: &cancellables)
    }

    func pause() { state = .paused }      // TODO(3.7): 冻结统计 / 自动暂停联动
    func resume() { state = .recording }

    /// 结束 → 生成 Track 入库（任务 3.10）。
    func finish() throws -> Track {
        location.stop(); altimeter.stop(); cancellables.removeAll()
        var track = Track(name: defaultName(), source: .recorded)
        track.distance = distance; track.movingTime = movingTime
        track.ascent = ascent; track.descent = descent; track.pointCount = pointCount
        try TrackRepository().save(track: track, points: buffer)
        reset()
        return track
    }

    private func ingest(_ loc: CLLocation) {
        guard state == .recording else { return }
        guard loc.horizontalAccuracy <= minAccuracy else { return }   // 任务 3.6
        if let last = lastLocation {
            let d = loc.distance(from: last)
            guard d >= minMove else { return }                         // 最小位移过滤
            distance += d
            // 海拔：气压计优先（任务 3.4）
            let ele = altimeter.relativeAltitude ?? loc.altitude
            if let lastEle = last.altitude as Double?, abs(loc.altitude - lastEle) >= ascentThreshold {
                if loc.altitude > lastEle { ascent += loc.altitude - lastEle } else { descent += lastEle - loc.altitude }
            }
            currentElevation = ele
        }
        buffer.append(TrackPoint(id: nil, trackId: session?.id ?? UUID(), segment: 0, seq: pointCount,
                                 lat: loc.coordinate.latitude, lon: loc.coordinate.longitude,
                                 elevation: loc.altitude, timestamp: loc.timestamp,
                                 speed: loc.speed >= 0 ? loc.speed : nil,
                                 horizontalAccuracy: loc.horizontalAccuracy))
        pointCount += 1
        lastLocation = loc
        // TODO(3.8): 每 N 点增量落盘 buffer，避免进程被杀丢数据
    }

    private func reset() {
        state = .idle; distance = 0; movingTime = 0; ascent = 0; descent = 0
        pointCount = 0; buffer.removeAll(); lastLocation = nil; session = nil
    }

    private func defaultName() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }
}
