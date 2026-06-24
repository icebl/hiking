import SwiftUI

/// 我的（任务 6.3）：入口聚合 + 设置 + （三期）账号占位。
struct MeView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("🥾").font(.largeTitle)
                        VStack(alignment: .leading) {
                            Text("本地模式").font(.headline)
                            Text("登录 / 注册 · 三期").font(.caption).foregroundColor(AppColor.primary)
                        }
                    }
                }
                Section("入口") {
                    NavigationLink { Text("// TODO(2.7) 离线地图下载/管理") } label: { Label("离线地图", systemImage: "square.3.stack.3d") }
                    NavigationLink { ImportPreviewView() } label: { Label("导入轨迹", systemImage: "square.and.arrow.down") }
                    NavigationLink { SettingsView() } label: { Label("设置", systemImage: "gearshape") }
                    NavigationLink { Text("徒步 App v0.1") } label: { Label("关于", systemImage: "info.circle") }
                }
            }
            .navigationTitle("我的")
        }
    }
}
