import SwiftUI

/// 根导航：底部 4 Tab（首页/地图/轨迹/我的）。
/// 地图为全屏沉浸、隐藏 Tab —— 这里用 fullScreenCover 承载，从首页/Tab 触发（任务 0.5）。
struct RootTabView: View {
    @State private var selection = 0
    @State private var showMap = false

    var body: some View {
        TabView(selection: $selection) {
            HomeView(openMap: { showMap = true })
                .tabItem { Label("首页", systemImage: "house.fill") }
                .tag(0)

            // 地图 Tab：点击后以全屏覆盖打开（隐藏 TabBar）
            Color.clear
                .tabItem { Label("地图", systemImage: "map.fill") }
                .tag(1)

            TracksView()
                .tabItem { Label("轨迹", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }
                .tag(2)

            MeView()
                .tabItem { Label("我的", systemImage: "person.fill") }
                .tag(3)
        }
        .tint(AppColor.primary)
        .onChange(of: selection) { new in
            if new == 1 { showMap = true; selection = 0 }   // 选中地图 → 全屏打开，Tab 复位
        }
        .fullScreenCover(isPresented: $showMap) {
            MapScreen()
        }
    }
}
