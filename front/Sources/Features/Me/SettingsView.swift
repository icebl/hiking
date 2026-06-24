import SwiftUI

/// 设置（任务 6.3）：采样/偏航/语音/海拔来源/坐标格式/同时记录。
/// 这些值后续接入 UserDefaults / AppStorage，并被记录与导航模块读取。
struct SettingsView: View {
    @AppStorage("sampleInterval") private var sampleInterval = 5      // 秒
    @AppStorage("minMove") private var minMove = 5                    // 米
    @AppStorage("autoPause") private var autoPause = true
    @AppStorage("altSource") private var altSource = "气压计优先"
    @AppStorage("offRouteThreshold") private var offRouteThreshold = 25  // 米
    @AppStorage("voiceAlert") private var voiceAlert = false
    @AppStorage("voiceInterval") private var voiceInterval = 5        // 分钟
    @AppStorage("recordWhileNav") private var recordWhileNav = true
    @AppStorage("coordFormat") private var coordFormat = "度 dd.ddddd°"

    var body: some View {
        Form {
            Section("记录") {
                Stepper("采样间隔 \(sampleInterval) 秒", value: $sampleInterval, in: 1...30)
                Stepper("最小位移 \(minMove) 米", value: $minMove, in: 1...50)
                Toggle("静止自动暂停", isOn: $autoPause)
                Picker("海拔来源", selection: $altSource) { Text("气压计优先").tag("气压计优先"); Text("仅 GPS").tag("仅 GPS") }
            }
            Section("导航") {
                Stepper("偏航阈值 \(offRouteThreshold) 米", value: $offRouteThreshold, in: 10...100, step: 5)
                Toggle("语音播报", isOn: $voiceAlert)
                if voiceAlert { Picker("播报间隔", selection: $voiceInterval) { Text("5 分钟").tag(5); Text("10 分钟").tag(10) } }
                Toggle("导航时同时记录", isOn: $recordWhileNav)
            }
            Section("通用") {
                Picker("坐标格式", selection: $coordFormat) {
                    Text("度 dd.ddddd°").tag("度 dd.ddddd°")
                    Text("度分秒 DMS").tag("度分秒 DMS")
                    Text("UTM").tag("UTM")
                }
                LabeledContent("账号 · 三期", value: "未登录")
            }
        }
        .navigationTitle("设置")
    }
}
