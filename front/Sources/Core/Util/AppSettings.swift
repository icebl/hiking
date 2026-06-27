import Foundation

/// 统一读取设置页（@AppStorage / UserDefaults）的值，供记录/导航/地图等非视图代码消费（任务 6.3）。
/// 注意：UserDefaults 未写入时 integer/bool 返回 0/false，故用 object(forKey:) 判空套默认值，与 SettingsView 默认保持一致。
enum AppSettings {
    private static var d: UserDefaults { .standard }

    static var minMove: Double {                 // 最小位移过滤（米）
        d.object(forKey: "minMove") != nil ? Double(d.integer(forKey: "minMove")) : 5
    }
    static var autoPause: Bool {                 // 静止自动暂停
        d.object(forKey: "autoPause") != nil ? d.bool(forKey: "autoPause") : true
    }
    static var useBarometer: Bool {              // 气压计辅助海拔（关则仅 GPS）
        d.object(forKey: "useBarometer") != nil ? d.bool(forKey: "useBarometer") : true
    }

    static var offRouteThreshold: Double {        // 偏航阈值（米）
        d.object(forKey: "offRouteThreshold") != nil ? Double(d.integer(forKey: "offRouteThreshold")) : 25
    }
    static var recordWhileNav: Bool {             // 导航时同时记录（默认）
        d.object(forKey: "recordWhileNav") != nil ? d.bool(forKey: "recordWhileNav") : true
    }
    static var waypointApproach: Double {         // 航点接近提醒半径（米）
        d.object(forKey: "waypointApproach") != nil ? Double(d.integer(forKey: "waypointApproach")) : 80
    }
    static var coordFormat: String {              // 坐标格式
        d.string(forKey: "coordFormat") ?? "度 dd.ddddd°"
    }
}
