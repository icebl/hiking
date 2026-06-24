import SwiftUI

@main
struct HikingApp: App {
    init() {
        _ = AppDatabase.shared      // 触发数据库初始化与迁移（任务 1.1）
        // TODO(3.8): 启动检测未完成的 RecordingSession，提示恢复
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}
