import SwiftUI
import UIKit

/// 系统分享面板（UIActivityViewController）封装：导出 GPX → 发微信/存文件等（任务 5.5）。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]  // 待分享内容，通常是导出的 GPX 文件 URL

    // 首次创建时构造系统分享控制器，把待分享项交给它。
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    // 分享内容一次性确定、无需随状态刷新，故空实现。
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
