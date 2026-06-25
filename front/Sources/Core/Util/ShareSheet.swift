import SwiftUI
import UIKit

/// 系统分享面板（UIActivityViewController）封装：导出 GPX → 发微信/存文件等（任务 5.5）。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
