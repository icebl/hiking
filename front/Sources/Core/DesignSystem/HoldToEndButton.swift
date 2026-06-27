import SwiftUI

/// 长按结束按钮（防误触，参照图35）：按住 seconds 秒，进度从左到右填充满后触发 action；
/// 中途松手则回弹取消。用于结束记录/结束导航。
struct HoldToEndButton: View {
    var title: String = "长按 3 秒结束"        // 按钮文案
    var seconds: Double = 3                    // 需按住的时长（秒），同时是进度填充动画时长
    let action: () -> Void                     // 按满后触发的回调

    @State private var progress: CGFloat = 0   // 进度 0~1，驱动填充条宽度

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: AppRadius.button).fill(AppColor.recording.opacity(0.55))
                RoundedRectangle(cornerRadius: AppRadius.button).fill(AppColor.recording)
                    .frame(width: geo.size.width * progress)
                Text(title).fontWeight(.semibold).foregroundColor(.white)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 52)
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.button))   // 整块矩形可响应触摸（含透明区）
        // pressing：按下→用 seconds 线性把进度推到 1（与触发时刻同步）；松手→0.2s 回弹归零（中途松手即取消）。
        // perform：仅在按满 minimumDuration 后触发，maximumDistance=80 容忍轻微滑动不取消。
        .onLongPressGesture(minimumDuration: seconds, maximumDistance: 80, pressing: { pressing in
            withAnimation(.linear(duration: pressing ? seconds : 0.2)) { progress = pressing ? 1 : 0 }
        }, perform: action)
    }
}
