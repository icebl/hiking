import SwiftUI

/// 收藏点列表（我的 → 收藏点）：总览所有独立收藏点（trackId=nil），点击编辑、左滑删除。
/// 收藏点在地图「工具 → 收藏点」模式下点地图添加。
struct FavoritesView: View {
    @State private var pois: [Waypoint] = []
    @State private var editing: Waypoint?

    var body: some View {
        List {
            if pois.isEmpty {
                Text("还没有收藏点。在地图「工具 → 收藏点」模式下点地图即可添加。")
                    .font(.subheadline).foregroundColor(AppColor.ink2).padding(.vertical, 8)
            } else {
                ForEach(pois) { w in
                    Button { editing = w } label: {
                        HStack(spacing: 12) {
                            Image(systemName: w.kind.icon)
                                .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                                .frame(width: 30, height: 30).background(w.kind.color).clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.name).foregroundColor(AppColor.ink)
                                Text(w.note?.isEmpty == false ? w.note! : w.kind.label)
                                    .font(.caption).foregroundColor(AppColor.ink2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(AppColor.ink2)
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(w) } label: { Label("删除", systemImage: "trash") }
                    }
                }
            }
        }
        .navigationTitle("收藏点")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .sheet(item: $editing) { w in WaypointEditSheet(waypoint: w) { reload() } }
    }

    private func reload() { pois = (try? TrackRepository().independentWaypoints()) ?? [] }
    private func delete(_ w: Waypoint) {
        try? TrackRepository().deleteWaypoint(id: w.id)
        WaypointPhotoStore.delete(w.id)
        reload()
    }
}
