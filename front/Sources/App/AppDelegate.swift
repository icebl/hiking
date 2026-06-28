import UIKit

/// App 代理：仅用于「按页面控制屏幕朝向」。
///
/// 背景：App 整体锁竖屏（见 project.yml），但记录页的「大字模式」需要横屏（强光/骑行车把场景）。
/// iOS 的朝向最终由 `application(_:supportedInterfaceOrientationsFor:)` 返回的 mask 决定，
/// 这里用一个全局可变的 `orientationMask` 作为开关：默认 `.portrait`，大字模式进入时改为横竖皆可、
/// 退出时还原，并调用 `apply(_:)` 让系统立即重新评估当前朝向。
final class AppDelegate: NSObject, UIApplicationDelegate {

    /// 当前允许的屏幕朝向。默认仅竖屏；大字模式临时放开为 `.allButUpsideDown`。
    /// 用 static 便于 SwiftUI 视图层（BigGaugeView）无需持有实例即可切换。
    static var orientationMask: UIInterfaceOrientationMask = .portrait

    /// 系统询问某窗口支持的朝向时，统一返回当前 mask。
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationMask
    }

    /// 设置新的允许朝向并让系统立刻重新评估、必要时旋转界面。
    /// - Parameter mask: 目标朝向集合（如大字模式用 `.allButUpsideDown`，退出用 `.portrait`）。
    /// 说明：iOS 16+ 用 `requestGeometryUpdate` 主动请求几何更新，
    ///       并 `setNeedsUpdateOfSupportedInterfaceOrientations` 触发上面的回调重读 mask。
    static func apply(_ mask: UIInterfaceOrientationMask) {
        orientationMask = mask
        // 取当前活跃的窗口场景（前台可见的那个）
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        // 主动请求几何更新到目标朝向（系统会在 mask 允许范围内调整）
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        // 让根控制器重新询问 supportedInterfaceOrientations，确保 mask 变化即时生效
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}
