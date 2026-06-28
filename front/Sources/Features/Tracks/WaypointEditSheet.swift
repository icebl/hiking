import SwiftUI
import UIKit

/// 航点/收藏点编辑表单（地图点图标、收藏点列表共用）：改名称/类型/备注，可删除，显示已存照片。
/// 保存/删除走 TrackRepository，并回调 onDone 让上层刷新。
struct WaypointEditSheet: View {
    let waypoint: Waypoint
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var note: String
    @State private var kind: WaypointKind

    init(waypoint: Waypoint, onDone: @escaping () -> Void) {
        self.waypoint = waypoint
        self.onDone = onDone
        _name = State(initialValue: waypoint.name)
        _note = State(initialValue: waypoint.note ?? "")
        _kind = State(initialValue: waypoint.kind)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $name)
                    Picker("类型", selection: $kind) {
                        ForEach(WaypointKind.allOrdered, id: \.self) { k in
                            Label(k.label, systemImage: k.icon).tag(k)
                        }
                    }
                    TextField("备注（可选）", text: $note, axis: .vertical).lineLimit(1...4)
                }
                // 有照片则展示
                if let img = WaypointPhotoStore.load(waypoint.id) {
                    Section("照片") {
                        Image(uiImage: img).resizable().scaledToFit()
                            .frame(maxHeight: 200).frame(maxWidth: .infinity)
                    }
                }
                Section {
                    Button(role: .destructive) { remove() } label: {
                        Label("删除收藏点", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("编辑收藏点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("保存") { save() }.fontWeight(.semibold) }
            }
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        try? TrackRepository().updateWaypoint(id: waypoint.id, name: n.isEmpty ? waypoint.name : n,
                                              note: note.isEmpty ? nil : note, kind: kind)
        onDone(); dismiss()
    }
    private func remove() {
        try? TrackRepository().deleteWaypoint(id: waypoint.id)
        WaypointPhotoStore.delete(waypoint.id)
        onDone(); dismiss()
    }
}
