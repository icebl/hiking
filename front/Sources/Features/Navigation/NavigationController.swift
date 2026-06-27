import Foundation
import CoreLocation
import Combine
import UIKit
import UserNotifications

/// 沿轨迹导航控制器（任务 4.x）：实时定位驱动 NavigationEngine，发布剩余/偏航/到达，触发震动+本地通知。
/// 本轮不做同时记录与语音播报。
final class NavigationController: ObservableObject {
    @Published var planCoordinates: [CLLocationCoordinate2D] = []
    @Published var remainingDistance: Double = 0    // m
    @Published var remainingAscent: Double = 0      // m
    @Published var distanceToLine: Double = 0       // 距计划线（m）
    @Published var isOffRoute = false
    @Published var arrived = false
    @Published var reverse = false
    @Published var isRecording = false              // 是否同时记录实走
    @Published var waypoints: [Waypoint] = []       // 沿线航点（地图显示）
    @Published var nearbyWaypoint: Waypoint?        // 当前最近的接近中航点（驱动横幅）
    @Published var nearbyWaypointDistance: Double = 0

    private let engine = NavigationEngine()
    private let location = LocationManager.shared
    private let recorder = RecordingController()     // 同时记录实走轨迹（任务 4.5）
    private var line: NavigationEngine.PlannedLine?
    private var cancellables = Set<AnyCancellable>()
    private var lastOffRoute = false
    private var running = false

    private let arriveThreshold: Double = 30        // 接近终点（m）
    private var nearbyIds: Set<UUID> = []           // 已提醒过的接近航点（滞回防重复）
    private var approachThreshold: Double = 80      // 进入此半径 → 接近提醒（m，读设置）
    private var clearThreshold: Double = 130        // 离开此半径 → 解除，可再次提醒（m，= 接近 + 50 滞回）

    func start(trackId: UUID, reverse: Bool, alsoRecord: Bool) {
        guard !running else { return }
        running = true
        self.reverse = reverse

        if alsoRecord { recorder.start(); isRecording = true }

        engine.offRouteThreshold = AppSettings.offRouteThreshold          // 读设置：偏航阈值
        engine.clearThreshold = max(5, AppSettings.offRouteThreshold - 10) // 滞回解除阈值
        approachThreshold = AppSettings.waypointApproach                  // 读设置：航点接近提醒半径
        clearThreshold = approachThreshold + 50                           // 解除阈值（滞回）

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

    func stop() {
        running = false
        cancellables.removeAll()
        if !isRecording { location.stop() }   // 同时记录时由 recorder 收尾停定位
    }

    /// 结束并保存实走轨迹（同时记录时）。
    func finishSaving() { _ = try? recorder.finish(); isRecording = false; location.stop() }
    /// 结束并丢弃实走轨迹。
    func finishDiscarding() { recorder.cancel(); isRecording = false; location.stop() }

    // MARK: - 定位驱动
    private func onLocation(_ loc: CLLocation) {
        guard let line else { return }
        let good = loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy <= 30
        let (dist, progress) = engine.update(current: loc, line: line, accuracyGood: good)
        distanceToLine = dist
        remainingDistance = engine.remaining(line: line, progress: progress)

        let idx = engine.lastMatchedIndex
        let passed = line.cumulativeAscent.indices.contains(idx) ? line.cumulativeAscent[idx] : 0
        remainingAscent = max(0, line.totalAscent - passed)

        // 到达终点仅提示（不自动结束，符合决策）
        if remainingDistance < arriveThreshold && !arrived { arrived = true }

        // 偏航跳变：震动 + 本地通知
        if engine.isOffRoute != lastOffRoute {
            lastOffRoute = engine.isOffRoute
            if engine.isOffRoute { fireOffRouteAlert(distance: dist) }
        }
        isOffRoute = engine.isOffRoute

        updateWaypointProximity(loc)
    }

    /// 沿线航点接近检测：进入 approachThreshold 触发一次提醒，离开 clearThreshold 后可再次提醒（滞回）。
    private func updateWaypointProximity(_ loc: CLLocation) {
        guard !waypoints.isEmpty else { return }
        var closest: (w: Waypoint, d: Double)?
        for w in waypoints {
            let d = loc.distance(from: CLLocation(latitude: w.lat, longitude: w.lon))
            if d <= approachThreshold {
                if closest == nil || d < closest!.d { closest = (w, d) }
                if !nearbyIds.contains(w.id) {
                    nearbyIds.insert(w.id)
                    fireWaypointAlert(w, distance: d)
                }
            } else if d > clearThreshold {
                nearbyIds.remove(w.id)
            }
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
    }

    private func fireWaypointAlert(_ w: Waypoint, distance: Double) {
        UINotificationFeedbackGenerator().notificationOccurred(w.kind == .danger ? .warning : .success)
        let content = UNMutableNotificationContent()
        content.title = "前方\(w.kind.label)"
        content.body = "约 \(Int(distance)) m · \(w.name)"
        content.sound = .default
        let req = UNNotificationRequest(identifier: "wp-\(w.id.uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func requestNotificationAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
