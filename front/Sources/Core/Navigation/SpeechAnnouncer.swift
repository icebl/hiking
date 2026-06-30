import Foundation
import AVFoundation

/// 导航语音播报（任务 4.4）：用系统 TTS 念中文提示（偏航/接近航点/到达/剩余里程）。
/// 播报时把音频会话设为 playback+duckOthers，压低正在播放的音乐；念完恢复，避免长期占用。
final class SpeechAnnouncer: NSObject, AVSpeechSynthesizerDelegate {
    // synth 仅在主线程使用；新 SDK 把本类视为 Sendable，AVSpeechSynthesizer 非 Sendable 会报错。
    // 用 nonisolated(unsafe) 单独豁免该属性的并发检查（语义安全：调用方均在主线程）。
    nonisolated(unsafe) private let synth = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "zh-CN")   // 中文嗓音（无则系统兜底）

    override init() {
        super.init()
        synth.delegate = self
    }

    /// 念一句话。空串忽略。多句会排队依次播报。
    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        activateSession()
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = AVSpeechUtteranceDefaultSpeechRate     // 默认语速，户外清晰
        synth.speak(u)
    }

    /// 立即停止并清空队列（结束导航时调用）。
    func stop() {
        synth.stopSpeaking(at: .immediate)
        deactivateSession()
    }

    /// 设为 playback 以便静音键下也能播报（导航语音应可闻）；duckOthers 压低其他音频。
    private func activateSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, options: [.duckOthers, .mixWithOthers])
        try? s.setActive(true)
    }

    /// 念完且队列空时释放会话，通知其他 App 恢复音量。
    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // 队列全部念完 → 恢复其他音频音量
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if !synthesizer.isSpeaking { deactivateSession() }
    }
}
