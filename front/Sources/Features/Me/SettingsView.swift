import SwiftUI

/// 设置（任务 6.3）：采样/偏航/语音/气压计/坐标格式/同时记录。
/// 改动先存草稿，**点底部「确认修改」后才写入生效**；否则不生效。
struct SettingsView: View {
    // 持久化（被记录/导航/地图读取，见 AppSettings）
    @AppStorage("sampleInterval") private var sampleInterval = 5
    @AppStorage("minMove") private var minMove = 5
    @AppStorage("autoPause") private var autoPause = true
    @AppStorage("useBarometer") private var useBarometer = true
    @AppStorage("offRouteThreshold") private var offRouteThreshold = 25
    @AppStorage("waypointApproach") private var waypointApproach = 80
    @AppStorage("voiceAlert") private var voiceAlert = false
    @AppStorage("voiceInterval") private var voiceInterval = 5
    @AppStorage("recordWhileNav") private var recordWhileNav = true
    @AppStorage("coordFormat") private var coordFormat = "度 dd.ddddd°"

    // 草稿（仅「确认」后写回上面）
    @State private var dSample = 5
    @State private var dMinMove = 5
    @State private var dAutoPause = true
    @State private var dBaro = true
    @State private var dOffRoute = 25
    @State private var dWpApproach = 80
    @State private var dVoice = false
    @State private var dVoiceInt = 5
    @State private var dRecNav = true
    @State private var dCoord = "度 dd.ddddd°"
    @State private var justSaved = false

    var body: some View {
        Form {
            Section("记录") {
                Stepper("采样间隔 \(dSample) 秒", value: $dSample, in: 1...30)
                Stepper("最小位移 \(dMinMove) 米", value: $dMinMove, in: 1...50)
                Toggle("静止自动暂停", isOn: $dAutoPause)
                Toggle("气压计辅助海拔", isOn: $dBaro)
            }
            Section("导航") {
                Stepper("偏航阈值 \(dOffRoute) 米", value: $dOffRoute, in: 10...100, step: 5)
                Stepper("航点接近提醒 \(dWpApproach) 米", value: $dWpApproach, in: 30...300, step: 10)
                Toggle("语音播报", isOn: $dVoice)
                if dVoice { Picker("播报间隔", selection: $dVoiceInt) { Text("5 分钟").tag(5); Text("10 分钟").tag(10) } }
                Toggle("导航时同时记录", isOn: $dRecNav)
            }
            Section("通用") {
                Picker("坐标格式", selection: $dCoord) {
                    Text("度 dd.ddddd°").tag("度 dd.ddddd°")
                    Text("度分秒 DMS").tag("度分秒 DMS")
                    Text("UTM").tag("UTM")
                }
                LabeledContent("账号 · 三期", value: "未登录")
            }
            Section {
                Button { apply() } label: {
                    Text(justSaved && !dirty ? "已保存 ✓" : "确认修改")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(dirty ? AppColor.primary : AppColor.ink2)
                }
                .disabled(!dirty)
            } footer: {
                Text("修改后需点「确认修改」才生效。")
            }
        }
        .navigationTitle("设置")
        .onAppear(perform: loadDraft)
    }

    private var dirty: Bool {
        dSample != sampleInterval || dMinMove != minMove || dAutoPause != autoPause
        || dBaro != useBarometer || dOffRoute != offRouteThreshold || dWpApproach != waypointApproach
        || dVoice != voiceAlert
        || dVoiceInt != voiceInterval || dRecNav != recordWhileNav || dCoord != coordFormat
    }

    private func loadDraft() {
        dSample = sampleInterval; dMinMove = minMove; dAutoPause = autoPause; dBaro = useBarometer
        dOffRoute = offRouteThreshold; dWpApproach = waypointApproach
        dVoice = voiceAlert; dVoiceInt = voiceInterval
        dRecNav = recordWhileNav; dCoord = coordFormat
    }

    private func apply() {
        sampleInterval = dSample; minMove = dMinMove; autoPause = dAutoPause; useBarometer = dBaro
        offRouteThreshold = dOffRoute; waypointApproach = dWpApproach
        voiceAlert = dVoice; voiceInterval = dVoiceInt
        recordWhileNav = dRecNav; coordFormat = dCoord
        justSaved = true
    }
}
