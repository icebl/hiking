import SwiftUI

/// 设置（任务 6.3）：采样/偏航/语音/气压计/坐标格式/同时记录。
/// 改动先存草稿，**点底部「确认修改」后才写入生效**；否则不生效。
struct SettingsView: View {
    // 持久化（被记录/导航/地图读取，见 AppSettings）
    @AppStorage("sampleInterval") private var sampleInterval = 5
    @AppStorage("minMove") private var minMove = 5
    @AppStorage("autoPause") private var autoPause = true
    @AppStorage("autoNameByPlace") private var autoNameByPlace = true
    @AppStorage("useBarometer") private var useBarometer = true
    @AppStorage("offRouteThreshold") private var offRouteThreshold = 25
    @AppStorage("waypointApproach") private var waypointApproach = 80
    @AppStorage("voiceAlert") private var voiceAlert = false
    @AppStorage("voiceInterval") private var voiceInterval = 5
    @AppStorage("recordWhileNav") private var recordWhileNav = true
    @AppStorage("coordFormat") private var coordFormat = "度 dd.ddddd°"
    @AppStorage("powerSaveGPS") private var powerSaveGPS = false
    @AppStorage("diagnostics") private var diagnostics = false
    @AppStorage("highContrastMap") private var highContrastMap = false

    // 草稿（界面只改这些，仅「确认」后写回上面持久化项）；初值会在 onAppear 由 loadDraft 覆盖
    @State private var dSample = 5         // 采样间隔(秒) 1…30
    @State private var dMinMove = 5        // 最小位移(米) 1…50
    @State private var dAutoPause = true   // 静止自动暂停
    @State private var dAutoName = true    // 结束时按地点自动命名
    @State private var dBaro = true        // 气压计辅助海拔
    @State private var dOffRoute = 25      // 偏航阈值(米) 10…100
    @State private var dWpApproach = 80    // 航点接近提醒(米) 30…300
    @State private var dVoice = false      // 语音播报开关
    @State private var dVoiceInt = 5       // 语音播报间隔(分) 5/10
    @State private var dRecNav = true      // 导航时同时记录
    @State private var dCoord = "度 dd.ddddd°"   // 坐标格式
    @State private var dPowerSave = false  // 省电定位（降精度+加大位移过滤）
    @State private var dDiag = false       // 诊断日志（电量/后台采样）
    @State private var dHighContrast = false // 高对比地图文字
    @State private var justSaved = false   // 刚点过确认（用于按钮显示「已保存 ✓」）

    var body: some View {
        Form {
            Section("记录") {
                Stepper("采样间隔 \(dSample) 秒", value: $dSample, in: 1...30)
                Stepper("最小位移 \(dMinMove) 米", value: $dMinMove, in: 1...50)
                Toggle("静止自动暂停", isOn: $dAutoPause)
                Toggle("气压计辅助海拔", isOn: $dBaro)
                Toggle("省电定位（降精度，更省电）", isOn: $dPowerSave)
                Toggle("按地点自动命名轨迹", isOn: $dAutoName)
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
                    Text("十进制 lat, lon").tag("十进制 lat, lon")
                    Text("度分秒 DMS").tag("度分秒 DMS")
                    Text("UTM").tag("UTM")
                }
                Toggle("高对比地图文字（强光更清晰）", isOn: $dHighContrast)
                LabeledContent("账号 · 三期", value: "未登录")
                Toggle("诊断日志（电量/后台采样）", isOn: $dDiag)
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

    /// 草稿与持久化值是否有差异：决定「确认修改」按钮可用与高亮，任一项不同即为脏。
    private var dirty: Bool {
        dSample != sampleInterval || dMinMove != minMove || dAutoPause != autoPause || dAutoName != autoNameByPlace
        || dBaro != useBarometer || dOffRoute != offRouteThreshold || dWpApproach != waypointApproach
        || dVoice != voiceAlert
        || dVoiceInt != voiceInterval || dRecNav != recordWhileNav || dCoord != coordFormat
        || dPowerSave != powerSaveGPS || dDiag != diagnostics || dHighContrast != highContrastMap
    }

    /// 进入页面时把持久化值灌入草稿，保证界面初始展示与已保存设置一致。
    private func loadDraft() {
        dSample = sampleInterval; dMinMove = minMove; dAutoPause = autoPause; dBaro = useBarometer
        dAutoName = autoNameByPlace
        dOffRoute = offRouteThreshold; dWpApproach = waypointApproach
        dVoice = voiceAlert; dVoiceInt = voiceInterval
        dRecNav = recordWhileNav; dCoord = coordFormat
        dPowerSave = powerSaveGPS; dDiag = diagnostics; dHighContrast = highContrastMap
    }

    /// 点「确认修改」时把草稿写回 @AppStorage 真正生效，并标记 justSaved 用于按钮反馈。
    private func apply() {
        sampleInterval = dSample; minMove = dMinMove; autoPause = dAutoPause; useBarometer = dBaro
        autoNameByPlace = dAutoName
        offRouteThreshold = dOffRoute; waypointApproach = dWpApproach
        voiceAlert = dVoice; voiceInterval = dVoiceInt
        recordWhileNav = dRecNav; coordFormat = dCoord
        powerSaveGPS = dPowerSave; diagnostics = dDiag; highContrastMap = dHighContrast
        justSaved = true
    }
}
