import Foundation
import CoreLocation
import Combine
import UIKit
import UserNotifications

/// 沿轨迹导航控制器（任务 4.x）：实时定位驱动 NavigationEngine，发布剩余/偏航/到达，触发震动+本地通知。
/// 本轮不做同时记录与语音播报。
final class NavigationController: ObservableObject {
    @Published var planCoordinates: [CLLocationCoordinate2D] = []  // 计划线坐标（按方向构建后供地图绘制）
    @Published var remainingDistance: Double = 0    // 到终点剩余距离，单位 m
    @Published var remainingAscent: Double = 0      // 剩余累计爬升，单位 m
    @Published var distanceToLine: Double = 0       // 当前位置到计划线的垂距，单位 m（偏航判据）
    @Published var isOffRoute = false               // 是否处于偏航状态（带滞回）
    @Published var arrived = false                  // 是否已到终点附近（仅提示，不自动结束）
    @Published var reverse = false                  // 导航方向：false 正向 / true 反向
    @Published var isRecording = false              // 是否同时记录实走
    @Published var waypoints: [Waypoint] = []       // 沿线航点（地图显示）
    @Published var nearbyWaypoint: Waypoint?        // 当前最近的接近中航点（驱动横幅）
    @Published var nearbyWaypointDistance: Double = 0

    private let engine = NavigationEngine()          // 投影匹配/偏航/剩余计算引擎
    private let location = LocationManager.shared
    private let recorder = RecordingController()     // 同时记录实走轨迹（任务 4.5）
    private var line: NavigationEngine.PlannedLine?  // 预处理后的计划线（含累计爬升表）
    private var cancellables = Set<AnyCancellable>()
    private var lastOffRoute = false                 // 上一帧偏航态，用于检测跳变只触发一次提醒
    private var running = false                       // 防重复 start 的运行标志

    private let arriveThreshold: Double = 30        // 接近终点（m）
    private var nearbyIds: Set<UUID> = []           // 已提醒过的接近航点（滞回防重复）
    private var approachThreshold: Double = 80      // 进入此半径 → 接近提醒（m，读设置）
    private var clearThreshold: Double = 130        // 离开此半径 → 解除，可再次提醒（m，= 接近 + 50 滞回）

    // 语音播报（任务 4.4）：设置页开关控制；偏航/接近/到达即时播报，剩余里程按间隔定时播报
    private let speaker = SpeechAnnouncer()
    private var voiceEnabled = false                // 本次导航是否启用语音（start 时读设置固定）
    private var voiceIntervalSec: TimeInterval = 300 // 剩余里程播报间隔（秒，读设置）
    private var lastVoiceAt = Date()                // 上次定时播报时刻，控制间隔

    /// 启动导航：构建计划线、读阈值设置、订阅定位流。
    /// 参数 trackId 计划轨迹；reverse 是否反向；alsoRecord 是否同时记录实走。前置 !running，防重入。
    func start(trackId: UUID, reverse: Bool, alsoRecord: Bool) {
        guard !running else { return }
        running = true
        self.reverse = reverse

        if alsoRecord { recorder.start(); isRecording = true }

        engine.offRouteThreshold = AppSettings.offRouteThreshold          // 读设置：偏航阈值
        engine.clearThreshold = max(5, AppSettings.offRouteThreshold - 10) // 滞回解除阈值
        approachThreshold = AppSettings.waypointApproach                  // 读设置：航点接近提醒半径
        clearThreshold = approachThreshold + 50                           // 解除阈值（滞回）
        voiceEnabled = AppSettings.voiceAlert                             // 读设置：语音播报开关
        voiceIntervalSec = TimeInterval(max(1, AppSettings.voiceInterval) * 60)
        lastVoiceAt = Date()                                             // 起点计时，首次播报在一个间隔后

        let pts = (try? TrackRepository().points(trackId: trackId)) ?? []
        waypoints = (try? TrackRepository().waypoints(trackId: trackId)) ?? []   // 沿线航点
        let l = NavigationEngine.buildLine(points: pts, reverse: reverse)
        line = l
        planCoordinates = l.points
        remainingDistance = l.totalDistance
        remainingAscent = l.totalAscent

        requestNotificationAuth()
        location.requestWhenInUse()
        location.start(background: true)
        location.$location.compactMap { $0 }.sink { [weak self] in self?.onLocation($0) }.store(in: &cancellables)
    }

    /// 停止导航：退订定位。仅在未同时记录时直接停定位，否则交由 recorder 收尾以免提前断流。
    func stop() {
        running = false
        cancellables.removeAll()
        speaker.stop()                         // 停止语音并释放音频会话
        if !isRecording { location.stop() }   // 同时记录时由 recorder 收尾停定位
    }

    /// 结束并保存实走轨迹（同时记录时）。
    func finishSaving() { _ = try? recorder.finish(); isRecording = false; location.stop() }
    /// 结束并丢弃实走轨迹。
    func finishDiscarding() { recorder.cancel(); isRecording = false; location.stop() }

    // MARK: - 定位驱动
    /// 每帧定位回调：更新剩余距离/爬升、偏航跳变提醒、航点接近检测。导航主流程。
    private func onLocation(_ loc: CLLocation) {
        guard let line else { return }
        let good = loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy <= 30  // 精度门限：差精度不参与偏航判定
        let (dist, progress) = engine.update(current: loc, line: line, accuracyGood: good)
        distanceToLine = dist
        remainingDistance = engine.remaining(line: line, progress: progress)

        // 用已匹配到的线上索引查累计爬升表，得已走爬升，反推剩余（clamp ≥0 防抖动负值）
        let idx = engine.lastMatchedIndex
        let passed = line.cumulativeAscent.indices.contains(idx) ? line.cumulativeAscent[idx] : 0
        remainingAscent = max(0, line.totalAscent - passed)

        // 到达终点仅提示（不自动结束，符合决策）；首次到达语音播报一次
        if remainingDistance < arriveThreshold && !arrived {
            arrived = true
            announce("已到达终点附近")
        }

        // 偏航跳变：仅在 在线→偏航 的状态翻转瞬间提醒一次，避免持续偏航时反复震动/推送
        if engine.isOffRoute != lastOffRoute {
            lastOffRoute = engine.isOffRoute
            if engine.isOffRoute { fireOffRouteAlert(distance: dist) }
        }
        isOffRoute = engine.isOffRoute

        updateWaypointProximity(loc)

        // 定时播报剩余里程：到达后不再播，偏航时也跳过（此刻该听偏航提醒）
        let nowTime = Date()
        if voiceEnabled, !arrived, !isOffRoute, nowTime.timeIntervalSince(lastVoiceAt) >= voiceIntervalSec {
            lastVoiceAt = nowTime
            announce(String(format: "剩余 %.1f 公里，爬升 %d 米", remainingDistance / 1000, Int(remainingAscent)))
        }
    }

    /// 语音播报（仅在本次导航启用语音时）。统一入口，便于各处复用与开关控制。
    private func announce(_ text: String) {
        guard voiceEnabled else { return }
        speaker.speak(text)
    }

    /// 沿线航点接近检测：进入 approachThreshold 触发一次提醒，离开 clearThreshold 后可再次提醒（滞回）。
    private func updateWaypointProximity(_ loc: CLLocation) {
        guard !waypoints.isEmpty else { return }
        var closest: (w: Waypoint, d: Double)?   // 进入半径内最近的航点，用于驱动横幅
        for w in waypoints {
            let d = loc.distance(from: CLLocation(latitude: w.lat, longitude: w.lon))
            if d <= approachThreshold {
                if closest == nil || d < closest!.d { closest = (w, d) }
                if !nearbyIds.contains(w.id) {       // 滞回上半：首次进入才提醒，记入已提醒集合
                    nearbyIds.insert(w.id)
                    fireWaypointAlert(w, distance: d)
                }
            } else if d > clearThreshold {           // 滞回下半：远到清除阈值外才复位，下次靠近可再提醒
                nearbyIds.remove(w.id)
            }
            // 介于 approach 与 clear 之间：保持原状态，避免边界来回抖动重复提醒
        }
        nearbyWaypoint = closest?.w
        nearbyWaypointDistance = closest?.d ?? 0
    }

    // MARK: - 提醒
    private func fireOffRouteAlert(distance: Double) {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)   // 震动
        let content = UNMutableNotificationContent()
        content.title = "已偏离计划线"
        content.body = "距计划线约 \(Int(distance)) m，请返回轨迹。"
        content.sound = .default
        let req = UNNotificationRequest(identifier: "offroute-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
        announce("已偏离计划线，距约 \(Int(distance)) 米，请返回")
    }

    private func fireWaypointAlert(_ w: Waypoint, distance: Double) {
        UINotificationFeedbackGenerator().notificationOccurred(w.kind == .danger ? .warning : .success)
        let content = UNMutableNotificationContent()
        content.title = "前方\(w.kind.label)"
        content.body = "约 \(Int(distance)) m · \(w.name)"
        content.sound = .default
        let req = UNNotificationRequest(identifier: "wp-\(w.id.uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
        announce("前方约 \(Int(distance)) 米，\(w.kind.label)，\(w.name)")
    }

    private func requestNotificationAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
