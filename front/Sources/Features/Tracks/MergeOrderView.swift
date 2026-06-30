import SwiftUI

/// 合并排序页：调整多条轨迹的拼接顺序、每条可选「正接/反接」，确认后按序合并为新轨迹。
/// 起点 = 第一条（按其方向）的头，终点 = 最后一条的尾——由用户在此定好，避免合并后起终点乱标。
/// 用上移/下移按钮排序（比 List 编辑态拖动更稳，行内的反接按钮也能正常点）。
struct MergeOrderView: View {
    let tracks: [Track]            // 初始顺序（来自轨迹库的选择顺序）
    var onDone: (Bool) -> Void     // 合并完成回调(true=成功)；由上层关闭并刷新列表

    @Environment(\.dismiss) private var dismiss
    @State private var rows: [Row]
    @State private var errorMsg: String?   // 注意：不能命名 error，会被 catch 隐式绑定的 error 遮蔽

    /// 一行：轨迹 id + 名称 + 是否反接（尾→头）。
    struct Row: Identifiable { let id: UUID; let name: String; var reversed: Bool }

    init(tracks: [Track], onDone: @escaping (Bool) -> Void) {
        self.tracks = tracks
        self.onDone = onDone
        _rows = State(initialValue: tracks.map { Row(id: $0.id, name: $0.name, reversed: false) })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("调整拼接顺序（上移/下移），必要时把某段「反接」。起点 = 第一条的头，终点 = 最后一条的尾。")
                    .font(.caption).foregroundColor(AppColor.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 10)

                List {
                    ForEach(rows) { row in
                        rowView(row)
                    }
                }
                .listStyle(.plain)

                Button { merge() } label: {
                    Text("合并为新轨迹").fontWeight(.semibold).foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(AppColor.primary).cornerRadius(AppRadius.button)
                }
                .padding(16)
            }
            .navigationTitle("合并轨迹").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } } }
            .alert("无法合并", isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })) {
                Button("好", role: .cancel) {}
            } message: { Text(errorMsg ?? "") }
        }
    }

    /// 单行：序号 + 名称/方向 + 反接切换 + 上移/下移。
    private func rowView(_ row: Row) -> some View {
        let idx = rows.firstIndex(where: { $0.id == row.id }) ?? 0
        return HStack(spacing: 10) {
            Text("\(idx + 1)").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                .frame(width: 22, height: 22).background(AppColor.primary).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).lineLimit(1)
                Text(row.reversed ? "反接（尾 → 头）" : "正接（头 → 尾）")
                    .font(.caption).foregroundColor(row.reversed ? AppColor.primary : AppColor.ink2)
            }
            Spacer()
            // 反接切换
            Button { rows[idx].reversed.toggle() } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(row.reversed ? AppColor.primary : AppColor.ink2)
                    .frame(width: 40, height: 40)
            }.buttonStyle(.plain)
            // 上移 / 下移
            VStack(spacing: 2) {
                Button { move(idx, by: -1) } label: {
                    Image(systemName: "chevron.up").frame(width: 30, height: 20)
                }.buttonStyle(.plain).disabled(idx == 0)
                Button { move(idx, by: 1) } label: {
                    Image(systemName: "chevron.down").frame(width: 30, height: 20)
                }.buttonStyle(.plain).disabled(idx == rows.count - 1)
            }
            .foregroundColor(AppColor.ink)
        }
        .padding(.vertical, 2)
    }

    /// 行上移/下移（by=-1 上移、+1 下移），边界保护。
    private func move(_ idx: Int, by: Int) {
        let j = idx + by
        guard rows.indices.contains(idx), rows.indices.contains(j) else { return }
        rows.swapAt(idx, j)
    }

    /// 执行合并：按当前顺序与每条方向调用 TrackEditor.merge，成功回调上层关闭刷新。
    private func merge() {
        do {
            let ordered = rows.map { (id: $0.id, reversed: $0.reversed) }
            if try TrackEditor.merge(ordered) != nil { onDone(true); dismiss() }
            else { errorMsg = "至少需要 2 条轨迹，且每条都有足够的点。" }
        } catch { errorMsg = "合并失败，请重试。" }
    }
}
