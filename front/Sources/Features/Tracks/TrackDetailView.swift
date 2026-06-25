import SwiftUI
import CoreLocation

/// 轨迹详情（任务 6.2 / 5.6）：地图 / 详情 页签 + 操作（导出/导航）。
struct TrackDetailView: View {
    let trackId: UUID
    @State private var tab = 0       // 0 地图 / 1 详情
    @State private var track: Track?
    @State private var points: [TrackPoint] = []
    @State private var waypoints: [Waypoint] = []
    @State private var coords: [CLLocationCoordinate2D] = []
    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var exportError: String?
    @StateObject private var mapCtrl = MapController()
    @State private var showKm = false
    @State private var toast: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) { Text("地图").tag(0); Text("详情").tag(1) }
                .pickerStyle(.segmented).padding()

            if tab == 0 {
                ZStack {
                    MapLibreView(controller: mapCtrl, trackCoordinates: coords,
                                 showsUserLocation: false, fitToTrack: true, showKmMarkers: showKm)
                    MapControlsOverlay(controller: mapCtrl, showKm: $showKm, onPlaceholder: showToast)
                    if let toast {
                        VStack {
                            Spacer()
                            Text(toast).font(.caption).foregroundColor(.white)
                                .padding(.vertical, 8).padding(.horizontal, 14)
                                .background(Color.black.opacity(0.75)).cornerRadius(10)
                                .padding(.bottom, 24)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                statsList
            }

            HStack(spacing: 12) {
                Button { exportGPX() } label: {
                    Text("导出").frame(maxWidth: .infinity).frame(height: 52)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColor.divider))
                }
                NavigationLink { NavigationRunView(trackId: trackId) } label: {
                    Text("使用轨迹导航").fontWeight(.semibold).foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 52).background(AppColor.primary).cornerRadius(14)
                }
            }.padding()
        }
        .navigationTitle(track?.name ?? "轨迹详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)   // 二级页隐藏底部 Tab（页面结构规则）
        .task {
            track = try? TrackRepository().track(id: trackId)
            points = (try? TrackRepository().points(trackId: trackId)) ?? []
            waypoints = (try? TrackRepository().waypoints(trackId: trackId)) ?? []
            coords = points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        }
        .sheet(isPresented: $showShare) {
            if let exportURL { ShareSheet(items: [exportURL]) }
        }
        .alert("导出失败", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(exportError ?? "") }
    }

    /// 导出 GPX（含航点）→ 系统分享面板（任务 5.5）。
    private func exportGPX() {
        guard let track else { return }
        do {
            exportURL = try GPXService().export(track: track, points: points, waypoints: waypoints)
            showShare = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    private var statsList: some View {
        List {
            if let t = track {
                row("距离", String(format: "%.2f km", t.distance / 1000))
                row("累计爬升", "\(Int(t.ascent)) m"); row("累计下降", "\(Int(t.descent)) m")
                row("运动用时", format(t.movingTime)); row("轨迹点数", "\(t.pointCount)")
                // TODO(5.6): 海拔剖面图（点击联动地图）
            }
        }
    }
    private func showToast(_ msg: String) {
        toast = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if toast == msg { toast = nil } }
    }
    private func row(_ l: String, _ v: String) -> some View { HStack { Text(l); Spacer(); Text(v).foregroundColor(AppColor.ink2) } }
    private func format(_ s: TimeInterval) -> String { let h = Int(s)/3600, m = (Int(s)%3600)/60; return String(format: "%02d:%02d", h, m) }
}
