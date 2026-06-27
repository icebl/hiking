import SwiftUI

/// 我的（任务 6.3）：入口聚合 + 设置 + （三期）账号占位。
struct MeView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Text("🥾").font(.system(size: 24))
                            .frame(width: 54, height: 54)
                            .background(AppColor.primaryTint).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("本地模式").font(.system(size: 17, weight: .bold))
                            HStack(spacing: 2) {
                                Text("登录 / 注册 · 三期").font(.caption)
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(AppColor.primary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                // 功能入口：离线地图 / 导入轨迹 / 设置 / 关于
                Section("入口") {
                    NavigationLink { OfflineMapsView() } label: { Label("离线地图", systemImage: "square.3.stack.3d") }
                    NavigationLink { ImportPreviewView() } label: { Label("导入轨迹", systemImage: "square.and.arrow.down") }
                    NavigationLink { SettingsView() } label: { Label("设置", systemImage: "gearshape") }
                    NavigationLink { AboutView() } label: {
                        HStack {
                            Label("关于", systemImage: "info.circle")
                            Spacer()
                            Text("v0.1").font(.caption).foregroundColor(AppColor.ink2)
                        }
                    }
                }
            }
            .navigationTitle("我的")
        }
    }
}
