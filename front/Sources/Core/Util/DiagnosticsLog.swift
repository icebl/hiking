import Foundation
import UIKit

/// 诊断日志（真机电量/后台续航实测用）：把会话期间的电量、电池状态、前后台、采点数等
/// 定时采样追加到 Documents/diagnostics.log，供导出分析。仅在设置开启「诊断日志」时记录。
enum DiagnosticsLog {
    private static let queue = DispatchQueue(label: "diagnostics.log")   // 串行写，避免并发写文件
    private static var monitoringConfigured = false

    /// 日志文件（Documents 下，可被「文件 App」与导出访问）。
    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("diagnostics.log")
    }

    /// 是否启用（读设置）。
    static var enabled: Bool { AppSettings.diagnostics }

    /// 记录一条事件（如 rec.start / nav.stop / pause）。带毫秒时间戳。
    static func event(_ message: String) {
        guard enabled else { return }
        append("[\(timestamp())] \(message)")
    }

    /// 采样一次设备状态：电量% + 充电状态 + 前后台 + 调用方附加信息。
    /// context 区分来源（rec/nav），extra 放采点数/距离等。
    static func sample(_ context: String, extra: String = "") {
        guard enabled else { return }
        configureMonitoringIfNeeded()
        let dev = UIDevice.current
        let pct = dev.batteryLevel < 0 ? -1 : Int(dev.batteryLevel * 100)   // -1 表示未知（未开监控/模拟器）
        let line = "[\(timestamp())] \(context) battery=\(pct)% \(batteryState(dev.batteryState)) "
            + "app=\(appState()) \(extra)"
        append(line)
    }

    /// 读取全部日志文本（诊断页展示用）。
    static func contents() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    /// 清空日志。
    static func clear() {
        queue.async { try? FileManager.default.removeItem(at: fileURL) }
    }

    // MARK: - 内部

    /// 开启电量监控（读取 batteryLevel 的前提）；只配一次。须在主线程。
    private static func configureMonitoringIfNeeded() {
        guard !monitoringConfigured else { return }
        monitoringConfigured = true
        if Thread.isMainThread { UIDevice.current.isBatteryMonitoringEnabled = true }
        else { DispatchQueue.main.async { UIDevice.current.isBatteryMonitoringEnabled = true } }
    }

    /// 追加一行（串行队列，文件不存在则创建）。
    private static func append(_ line: String) {
        queue.async {
            let data = (line + "\n").data(using: .utf8) ?? Data()
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try? data.write(to: fileURL)   // 首次：新建文件
            }
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm:ss.SSS"
        return f.string(from: Date())
    }

    private static func batteryState(_ s: UIDevice.BatteryState) -> String {
        switch s {
        case .charging:    return "charging"
        case .full:        return "full"
        case .unplugged:   return "unplugged"
        default:           return "unknown"
        }
    }

    /// 前后台状态（须主线程读取 applicationState）。
    private static func appState() -> String {
        guard Thread.isMainThread else { return "?" }
        switch UIApplication.shared.applicationState {
        case .active:     return "fg"
        case .inactive:   return "inactive"
        case .background: return "bg"
        @unknown default: return "?"
        }
    }
}
