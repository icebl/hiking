import SwiftUI

/// 设计 Token（对应 UI/设计规范.md，任务 0.6）。
enum AppColor {
    static let primary     = Color(hex: 0x1F9D55)
    static let primaryDark = Color(hex: 0x15803D)
    static let primaryTint = Color(hex: 0xE6F6EC)
    static let recording   = Color(hex: 0xFF3B30)
    static let warning     = Color(hex: 0xF2730D)
    static let info        = Color(hex: 0x2D7FF9)
    static let contour     = Color(hex: 0x36C5C0)
    static let ink         = Color(hex: 0x1C1C1E)
    static let ink2        = Color(hex: 0x6B7280)
    static let divider     = Color(hex: 0xE5E7EB)
}

enum AppRadius { static let card: CGFloat = 16; static let button: CGFloat = 14; static let control: CGFloat = 22 }
enum AppSpacing { static let s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24 }

extension Color {
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
    static func dataBig() -> Font { .system(size: 38, weight: .bold, design: .rounded).monospacedDigit() }
    static func dataMid() -> Font { .system(size: 21, weight: .semibold, design: .rounded).monospacedDigit() }
}
