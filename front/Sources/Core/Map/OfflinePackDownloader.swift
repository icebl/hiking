import Foundation
import CoreLocation
import MapLibre

/// 官方离线下载封装（任务 2.7 / S2-B）：用 MLNOfflineStorage 把框选区域的 ESRI 卫星瓦片
/// 下载并钉入 MapLibre 自带离线缓存；离线进到该区域时，在线 ESRI 底图按 URL 命中缓存渲染。
final class OfflinePackDownloader: ObservableObject {
    enum Phase: Equatable { case idle, downloading, finished, failed }
    @Published var phase: Phase = .idle
    @Published var completed: Int = 0
    @Published var expected: Int = 0

    private var pack: MLNOfflinePack?

    init() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(progressChanged(_:)),
                       name: NSNotification.Name.MLNOfflinePackProgressChanged, object: nil)
        nc.addObserver(self, selector: #selector(errorReceived(_:)),
                       name: NSNotification.Name.MLNOfflinePackError, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    func start(sw: CLLocationCoordinate2D, ne: CLLocationCoordinate2D, minZoom: Int, maxZoom: Int, name: String) {
        let bounds = MLNCoordinateBounds(sw: sw, ne: ne)
        let region = MLNTilePyramidOfflineRegion(styleURL: OnlineRasterStyle.styleURL(), bounds: bounds,
                                                 fromZoomLevel: Double(minZoom), toZoomLevel: Double(maxZoom))
        let ctx = name.data(using: .utf8) ?? Data()
        phase = .downloading; completed = 0; expected = 0
        MLNOfflineStorage.shared.addPack(for: region, withContext: ctx) { [weak self] pack, error in
            guard let self else { return }
            if let pack { self.pack = pack; pack.resume() } else { self.phase = .failed }
        }
    }

    func cancel() {
        if let pack { MLNOfflineStorage.shared.removePack(pack, withCompletionHandler: nil) }
        pack = nil
        phase = .idle
    }

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
