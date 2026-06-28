import SwiftUI
import CoreLocation

/// 裁剪首尾（轨迹编辑）：地图预览「保留段」红线 + 双滑块选起/终点下标，保存为新轨迹。
/// 双滑块约束 from < to；保留段随滑块实时更新（trackCoordinates = 切片）。
struct TrackTrimView: View {
    let trackId: UUID
    var onSaved: () -> Void               // 保存成功回调（父视图刷新/提示）
    @Environment(\.dismiss) private var dismiss
    @StateObject private var mapCtrl = MapController()

    @State private var coords: [CLLocationCoordinate2D] = []   // 全部轨迹点坐标
    @State private var fromIdx: Double = 0                     // 保留起点下标
    @State private var toIdx: Double = 0                       // 保留终点下标
    @State private var errorMsg: String?

    /// 当前保留的坐标切片（from…to）。
    private var kept: [CLLocationCoordinate2D] {
        let lo = Int(fromIdx), hi = Int(toIdx)
        guard !coords.isEmpty, lo <= hi, hi < coords.count else { return [] }
        return Array(coords[lo...hi])
    }

    var body: some View {
        VStack(spacing: 0) {
            MapLibreView(controller: mapCtrl, trackCoordinates: kept,
                         showsUserLocation: false, fitToTrack: true)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                Text("保留 \(kept.count) / \(coords.count) 点").font(.subheadline).foregroundColor(AppColor.ink2)

                // 起点滑块（不得越过终点）
                HStack {
                    Text("起点").font(.caption).foregroundColor(AppColor.ink2).frame(width: 36, alignment: .leading)
                    Slider(value: $fromIdx, in: 0...Double(max(1, coords.count - 1)), step: 1)
                        .onChange(of: fromIdx) { _ in if fromIdx > toIdx - 1 { fromIdx = max(0, toIdx - 1) } }
                }
                // 终点滑块（不得越过起点）
                HStack {
                    Text("终点").font(.caption).foregroundColor(AppColor.ink2).frame(width: 36, alignment: .leading)
                    Slider(value: $toIdx, in: 0...Double(max(1, coords.count - 1)), step: 1)
                        .onChange(of: toIdx) { _ in if toIdx < fromIdx + 1 { toIdx = min(Double(coords.count - 1), fromIdx + 1) } }
                }

                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Text("取消").frame(maxWidth: .infinity).frame(height: 48)
                            .overlay(RoundedRectangle(cornerRadius: AppRadius.button).stroke(AppColor.divider))
                    }
                    Button { saveTrim() } label: {
                        Text("保存为新轨迹").fontWeight(.semibold).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(AppColor.primary).cornerRadius(AppRadius.button)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("裁剪首尾")
        .navigationBarTitleDisplayMode(.inline)
        .alert("裁剪失败", isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(errorMsg ?? "") }
        .task {
            // 一次性加载轨迹点；终点滑块默认到末尾（即默认不裁剪）
            let pts = (try? TrackRepository().points(trackId: trackId)) ?? []
            coords = pts.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            fromIdx = 0
            toIdx = Double(max(1, coords.count - 1))
        }
    }

    /// 保存裁剪结果为新轨迹。
    private func saveTrim() {
        do {
            guard try TrackEditor.trimSave(trackId, from: Int(fromIdx), to: Int(toIdx)) != nil else {
                errorMsg = "裁剪范围无效"; return
            }
            onSaved(); dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}
