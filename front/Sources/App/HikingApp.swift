import SwiftUI
import UIKit

/// App 入口：进程启动时一次性完成数据库初始化与全局导航栏外观配置，根视图为 RootTabView。
@main
struct HikingApp: App {
    /// 进程启动初始化：触发数据库 + 设定全局 UIKit 外观（在 SwiftUI 视图层级建立前生效）。
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
