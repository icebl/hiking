import SwiftUI
import CoreLocation

/// 轨迹详情（任务 6.2 / 5.6）：地图 / 详情 页签 + 操作（导出/导航）。
struct TrackDetailView: View {
    let trackId: UUID
    @State private var tab = 0       // 0 地图 / 1 详情
    @State private var track: Track?
    @State private var coords: [CLLocationCoordinate2D] = []

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) { Text("地图").tag(0); Text("详情").tag(1) }
                .pickerStyle(.segmented).padding()

            if tab == 0 {
                MapLibreView(trackCoordinates: coords, showsUserLocation: false, fitToTrack: true)
                    .frame(maxHeight: .infinity)
            } else {
                statsList
            }

            HStack(spacing: 12) {
                NavigationLink { /* TODO(5.5) 导出轨迹文件页 */ Text("导出轨迹文件（GPX）") } label: {
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
        .task {
            track = try? TrackRepository().track(id: trackId)
            let pts = (try? TrackRepository().points(trackId: trackId)) ?? []
            coords = pts.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
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
    private func row(_ l: String, _ v: String) -> some View { HStack { Text(l); Spacer(); Text(v).foregroundColor(AppColor.ink2) } }
    private func format(_ s: TimeInterval) -> String { let h = Int(s)/3600, m = (Int(s)%3600)/60; return String(format: "%02d:%02d", h, m) }
}
