import Foundation
import CoreLocation
import MapLibre

/// 官方离线下载封装（任务 2.7 / S2-B）：用 MLNOfflineStorage 把框选区域的 ESRI 卫星瓦片
/// 下载并钉入 MapLibre 自带离线缓存；离线进到该区域时，在线 ESRI 底图按 URL 命中缓存渲染。
final class OfflinePackDownloader: ObservableObject {
    enum Phase: Equatable { case idle, downloading, finished, failed }
    @Published var phase: Phase = .idle
    @Published var completed: Int = 0   // 已完成资源数（瓦片等）
    @Published var expected: Int = 0    // 预计资源总数；进度 = completed/expected

    private var pack: MLNOfflinePack?   // 当前下载任务句柄（取消/进度比对用）

    init() {
        // 进度/错误通过 NotificationCenter 广播（无回调），构造时订阅、deinit 退订
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(progressChanged(_:)),
                       name: NSNotification.Name.MLNOfflinePackProgressChanged, object: nil)
        nc.addObserver(self, selector: #selector(errorReceived(_:)),
                       name: NSNotification.Name.MLNOfflinePackError, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    /// 开始下载指定矩形范围 + 缩放区间的离线包。
    /// region 的 styleURL 复用在线 ESRI 样式 → 下载的瓦片按相同 URL 钉入缓存，离线时自动命中。
    func start(sw: CLLocationCoordinate2D, ne: CLLocationCoordinate2D, minZoom: Int, maxZoom: Int, name: String) {
        let bounds = MLNCoordinateBounds(sw: sw, ne: ne)
        let region = MLNTilePyramidOfflineRegion(styleURL: OnlineRasterStyle.styleURL(), bounds: bounds,
                                                 fromZoomLevel: Double(minZoom), toZoomLevel: Double(maxZoom))
        let ctx = name.data(using: .utf8) ?? Data()   // 包名存入 context，供日后列举/识别
        phase = .downloading; completed = 0; expected = 0
        // 注册 pack 成功后须显式 resume() 才真正开始；失败则标记 .failed
        MLNOfflineStorage.shared.addPack(for: region, withContext: ctx) { [weak self] pack, error in
            guard let self else { return }
            if let pack { self.pack = pack; pack.resume() } else { self.phase = .failed }
        }
    }

    /// 取消并从离线存储中移除当前包（释放已下载缓存），回到 idle。
    func cancel() {
        if let pack { MLNOfflineStorage.shared.removePack(pack, withCompletionHandler: nil) }
        pack = nil
        phase = .idle
    }

    // 进度回调：MapLibre 在后台线程广播；先用 === 过滤掉非本任务的包，再回主线程更新 @Published
    @objc private func progressChanged(_ note: Notification) {
        guard let p = note.object as? MLNOfflinePack, p === pack else { return }
        let pr = p.progress
        DispatchQueue.main.async {
            self.completed = Int(pr.countOfResourcesCompleted)
            self.expected = Int(pr.countOfResourcesExpected)
            if p.state == .complete { self.phase = .finished }
        }
    }
    @objc private func errorReceived(_ note: Notification) {
        guard let p = note.object as? MLNOfflinePack, p === pack else { return }
        DispatchQueue.main.async { self.phase = .failed }
    }
}
