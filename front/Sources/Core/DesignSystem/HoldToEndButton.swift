import SwiftUI

/// 长按结束按钮（防误触，参照图35）：按住 seconds 秒，进度从左到右填充满后触发 action；
/// 中途松手则回弹取消。用于结束记录/结束导航。
struct HoldToEndButton: View {
    var title: String = "长按 3 秒结束"
    var seconds: Double = 3
    let action: () -> Void

    @State private var progress: CGFloat = 0

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
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.button))
        .onLongPressGesture(minimumDuration: seconds, maximumDistance: 80, pressing: { pressing in
            withAnimation(.linear(duration: pressing ? seconds : 0.2)) { progress = pressing ? 1 : 0 }
        }, perform: action)
    }
}
