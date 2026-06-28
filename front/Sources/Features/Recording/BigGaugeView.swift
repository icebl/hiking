import SwiftUI
import UIKit

/// 记录页「大字模式」：全屏深色高对比面板，专为强光 / 骑行车把「扫一眼」场景。
/// 共用同一 `RecordingController`（数据实时刷新）。竖屏 2×2、横屏一排，字号随空间自适应。
/// 仅本面板允许横屏（onAppear 放开朝向 mask、onDisappear 还原），并临时禁止自动熄屏。
struct BigGaugeView: View {
    // 注意：新参数一律追加在末尾，避免 memberwise init 顺序报错。
    @ObservedObject var ctrl: RecordingController
    var onExit: () -> Void     // 退出大字模式（返回普通记录页）
    var onEnd: () -> Void      // 长按结束记录（由上层关闭 cover 后走 endRecording）

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height   // 宽>高即横屏，驱动布局切换
            ZStack {
                Color.black.ignoresSafeArea()                  // 纯黑底：强光对比最强、OLED 省电
                VStack(spacing: landscape ? 10 : 18) {
                    statusBar
                    gaugeGrid(landscape: landscape)
                        .frame(maxHeight: .infinity)           // 读数区吃满中间空白
                    controls
                }
                .padding(landscape ? 16 : 20)
            }
        }
        .statusBarHidden(true)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true    // 防熄屏：扫一眼场景需常亮
            AppDelegate.apply(.allButUpsideDown)               // 放开横屏（仅本面板）
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false   // 还原系统自动熄屏
            AppDelegate.apply(.portrait)                       // 还原锁竖屏
        }
    }

    // MARK: - 顶部状态条（状态点 + 文案 + 退出大字）

    private var statusBar: some View {
        HStack(spacing: 10) {
            Circle().fill(ctrl.isAutoPaused ? Color.gray : AppColor.recording)
                .frame(width: 11, height: 11)
            Text(statusText).font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
            Spacer()
            Button(action: onExit) {       // 收起回普通记录页
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 44, height: 44)
            }
        }
    }

    /// 顶部状态文案：暂停 / 自动暂停 / 记录中。
    private var statusText: String {
        switch ctrl.state {
        case .paused: return "已暂停"
        default:      return ctrl.isAutoPaused ? "自动暂停中 · 静止" : "记录中"
        }
    }

    // MARK: - 4 项读数网格（距离 / 速度 / 用时 / 海拔）

    @ViewBuilder
    private func gaugeGrid(landscape: Bool) -> some View {
        if landscape {
            // 横屏：一排 4 列，铺满宽度
            HStack(spacing: 14) {
                gauge(distText, "km", "距离")
                gauge(speedText, "km/h", "速度")
                gauge(timeString(ctrl.movingTime), "", "用时")
                gauge(eleText, "m", "海拔")
            }
        } else {
            // 竖屏：2×2
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    gauge(distText, "km", "距离")
                    gauge(speedText, "km/h", "速度")
                }
                HStack(spacing: 14) {
                    gauge(timeString(ctrl.movingTime), "", "用时")
                    gauge(eleText, "m", "海拔")
                }
            }
        }
    }

    /// 单格读数：标签 + 超大数值（可随格子缩放）+ 单位。白字黑底、等宽数字防跳动。
    private func gauge(_ value: String, _ unit: String, _ label: String) -> some View {
        VStack(spacing: 6) {
            Text(label).font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 80, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(.white)
                    .lineLimit(1).minimumScaleFactor(0.3)   // 数值过长时自动缩小填满
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.06))               // 极淡分块底，强光下区分各格
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - 底部控制（暂停/继续 + 长按结束）

    private var controls: some View {
        HStack(spacing: 14) {
            Button { ctrl.state == .paused ? ctrl.resume() : ctrl.pause() } label: {
                Text(ctrl.state == .paused ? "继续" : "暂停")
                    .font(.system(size: 19, weight: .bold)).foregroundColor(.black)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.button))
            }
            HoldToEndButton(title: "长按 3 秒结束") { onEnd() }
        }
    }

    // MARK: - 读数格式化（与 RecordingView 同逻辑）

    /// 累计距离（km，两位小数）。
    private var distText: String { String(format: "%.2f", ctrl.distance / 1000) }
    /// 瞬时速度（km/h）：由定位 speed(m/s) 换算；无效显示 --。
    private var speedText: String {
        guard let s = ctrl.currentSpeed, s >= 0 else { return "--" }
        return String(format: "%.1f", s * 3.6)
    }
    /// 当前海拔（m）：气压计相对值优先，否则 GPS；无则 --。
    private var eleText: String { ctrl.currentElevation.map { "\(Int($0))" } ?? "--" }
    /// 秒数格式化为 HH:MM:SS。
    private func timeString(_ s: TimeInterval) -> String {
        let t = Int(s); return String(format: "%02d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }
}
