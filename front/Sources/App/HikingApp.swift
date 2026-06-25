import SwiftUI
import UIKit

@main
struct HikingApp: App {
    init() {
        _ = AppDatabase.shared      // 触发数据库初始化与迁移（任务 1.1）
        // 顶部大标题字号：系统默认 34pt → 24pt（仅改字体，不动导航栏背景）
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 24, weight: .bold)
        ]
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}
