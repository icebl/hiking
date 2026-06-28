import SwiftUI

/// 设计 Token（对应 UI/设计规范.md，任务 0.6）。
enum AppColor {
    static let primary     = Color(hex: 0x1F9D55)   // 主品牌绿（主按钮/强调/Tab tint）
    static let primaryDark = Color(hex: 0x15803D)   // 主色加深（按下态/渐变）
    static let primaryTint = Color(hex: 0xE6F6EC)   // 主色浅底（选中背景/标签底）
    static let recording   = Color(hex: 0xFF3B30)   // 记录中红（实时轨迹/结束按钮）
    static let warning     = Color(hex: 0xF2730D)   // 警示橙
    static let info        = Color(hex: 0x2D7FF9)   // 信息蓝
    static let contour      = Color(hex: 0x36C5C0)  // 等高线青
    static let ink         = Color(hex: 0x1C1C1E)   // 主文字（近黑）
    static let ink2        = Color(hex: 0x6B7280)   // 次级文字（灰）
    static let divider     = Color(hex: 0xE5E7EB)   // 分割线/描边浅灰
}

/// 圆角 Token：卡片 / 按钮 / 控件（胶囊形）。单位 pt。
enum AppRadius { static let card: CGFloat = 16; static let button: CGFloat = 14; static let control: CGFloat = 22 }
/// 间距 Token：s/m/l/xl 四档统一布局留白。单位 pt。
enum AppSpacing { static let s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24 }

extension AppColor {
    /// 地图浮层底色：高对比模式更深(0.9)，户外强光下文字更清晰；常态 0.72。
    static func mapScrim(_ highContrast: Bool) -> Color { Color.black.opacity(highContrast ? 0.9 : 0.72) }
}

extension Color {
    /// 用 0xRRGGBB 整型十六进制构造 sRGB 不透明颜色（便于直接写设计稿色值）。
    init(hex: UInt) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// 数据读数：圆体等宽数字（任务 0.6 / 视觉规范）。
extension Font {
    // 等宽数字(monospacedDigit)：读数跳动时数字不抖动。
    static func dataBig() -> Font { .system(size: 38, weight: .bold, design: .rounded).monospacedDigit() }     // 主读数（如总里程）
    static func dataMid() -> Font { .system(size: 21, weight: .semibold, design: .rounded).monospacedDigit() }  // 次读数（如配速/海拔）
}
