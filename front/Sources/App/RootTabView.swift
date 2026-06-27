import SwiftUI

/// 崩溃恢复协调器：启动检测到未结束的记录会话时驱动弹窗。
final class RecoveryCoordinator: ObservableObject {
    static let shared = RecoveryCoordinator()
    /// 待恢复的未结束会话；非 nil 时 RootTabView 弹出“上次记录未结束”对话框。
    @Published var session: RecordingSession?
}

/// 根导航：底部 4 Tab（首页/地图/轨迹/我的）。
/// 地图为全屏沉浸、隐藏 Tab —— 用 fullScreenCover 承载（任务 0.5）。
struct RootTabView: View {
    @State private var selection = 0                  // 当前选中 Tab（地图/轨迹会被拦截回首页）
    @State private var cover: Cover?                  // 当前全屏覆盖目标；nil 表示无覆盖
    @StateObject private var importer = ImportCoordinator.shared   // 外部文件导入协调（onOpenURL → 预览）
    @StateObject private var recovery = RecoveryCoordinator.shared // 崩溃恢复协调（未结束会话续记）

    /// 全屏覆盖目标（地图 / 轨迹库 / 崩溃续记），合并为单一 item 避免多 cover 冲突。
    enum Cover: Identifiable {
        case map
        case tracks
        case resume(UUID)
        var id: String {
            switch self {
            case .map: return "map"
            case .tracks: return "tracks"
            case .resume(let u): return "resume-\(u.uuidString)"
            }
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            HomeView(openMap: { cover = .map })
                .tabItem { Label("首页", systemImage: "house.fill") }.tag(0)

            Color.clear
                .tabItem { Label("地图", systemImage: "map.fill") }.tag(1)

            // 轨迹 Tab：全屏沉浸（无底部 Tab），同地图
            Color.clear
                .tabItem { Label("轨迹", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }.tag(2)

            MeView()
                .tabItem { Label("我的", systemImage: "person.fill") }.tag(3)
        }
        .tint(AppColor.primary)
        // 地图/轨迹 Tab 本身是空占位：选中即转成全屏覆盖，并把 selection 复位回首页（0），
        // 这样关闭全屏后落回首页而非停在空白占位页。
        .onChange(of: selection) { new in
            if new == 1 { cover = .map; selection = 0 }       // 地图 → 全屏
            else if new == 2 { cover = .tracks; selection = 0 } // 轨迹 → 全屏
        }
        .fullScreenCover(item: $cover) { c in
            switch c {
            case .map: MapScreen()
            case .tracks: NavigationStack { TracksView() }
            case .resume(let id): RecordingView(resumeSessionId: id)
            }
        }
        // 微信/系统“用本应用打开” → 接收文件 → 导入预览
        .onOpenURL { importer.pendingURL = $0 }
        .sheet(isPresented: Binding(
            get: { importer.pendingURL != nil },
            set: { if !$0 { importer.pendingURL = nil } }
        )) {
            NavigationStack { ImportPreviewView(fileURL: importer.pendingURL) }
        }
        // 崩溃恢复：启动检测未结束会话
        .onAppear {
            if recovery.session == nil {
                recovery.session = (try? TrackRepository().activeSessions())?.first
            }
        }
        .confirmationDialog("上次记录未结束", isPresented: Binding(
            get: { recovery.session != nil },
            set: { if !$0 { recovery.session = nil } }
        ), titleVisibility: .visible, presenting: recovery.session) { s in
            Button("继续记录") {
                let id = s.id; recovery.session = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { cover = .resume(id) }
            }
            Button("结束并保存") { RecordingController.finalizeRecovered(s); recovery.session = nil }
            Button("丢弃", role: .destructive) { RecordingController.discard(s); recovery.session = nil }
            Button("稍后再说", role: .cancel) { recovery.session = nil }
        } message: { _ in
            Text("检测到一段未结束的轨迹记录，是否继续？")
        }
    }
}
