import SwiftUI
import UIKit

/// 航点类型的展示样式（标注点管理）：中文名 / SF Symbol 图标 / 颜色。
/// 统一供：地图标注、详情页列表、记录中打点选择器复用。
extension WaypointKind {
    /// 选择器/列表展示顺序。
    static var allOrdered: [WaypointKind] { [.camp, .water, .junction, .danger, .photo, .other] }

    var label: String {
        switch self {
        case .camp:     return "营地"
        case .water:    return "水源"
        case .junction: return "岔路"
        case .danger:   return "危险"
        case .photo:    return "拍照"
        case .other:    return "其他"
        }
    }

    var icon: String {
        switch self {
        case .camp:     return "tent.fill"
        case .water:    return "drop.fill"
        case .junction: return "arrow.triangle.branch"
        case .danger:   return "exclamationmark.triangle.fill"
        case .photo:    return "camera.fill"
        case .other:    return "mappin"
        }
    }

    /// 颜色 RGB（十六进制）。
    var hex: UInt {
        switch self {
        case .camp:     return 0x8A5A2B   // 棕
        case .water:    return 0x2D7FF9   // 蓝
        case .junction: return 0xF2730D   // 橙
        case .danger:   return 0xFF3B30   // 红
        case .photo:    return 0x36C5C0   // 青
        case .other:    return 0x6B7280   // 灰
        }
    }

    var color: Color { Color(hex: hex) }

    var uiColor: UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
