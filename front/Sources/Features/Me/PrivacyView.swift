import SwiftUI

/// 隐私说明（发布收尾）：用通俗中文说明收集哪些数据、用途、存储位置与权限控制。
/// 核心立场：本地优先，不上传服务器；云同步为三期，启用前不外传。
struct PrivacyView: View {
    var body: some View {
        List {
            Section {
                Text("路迹是本地优先的徒步应用。你的轨迹、航点和照片只保存在本机，不会上传到任何服务器。")
                    .font(.subheadline)
            }

            Section("我们使用的数据") {
                item("位置", "用于记录与导航轨迹、计算距离/爬升、判断偏航。为支持锁屏与后台连续记录，可能在后台使用定位。")
                item("运动与气压计", "可选，开启后用气压计获得更稳定的海拔数据。")
                item("相机 / 相册", "仅在你「拍照打点」时使用，照片作为标注点配图保存在本机。")
            }

            Section("数据如何存储") {
                item("本地存储", "轨迹、航点、照片、离线地图均存于 App 沙盒内，不联网外传。")
                item("网络请求", "仅在线底图会向地图服务商（Esri）请求影像瓦片；不发送你的轨迹数据。")
                item("无广告 / 无统计", "不集成第三方广告或行为统计 SDK。")
                item("云同步 · 三期", "未来的云端同步为可选功能，启用前不会上传任何数据。")
            }

            Section("你的控制权") {
                item("权限", "定位、运动、相机权限都可在 系统设置 → 路迹 中随时关闭。")
                item("删除", "删除轨迹或航点即从本机移除对应数据与照片。")
                item("导出", "可随时把轨迹导出为 GPX / KML，数据完全归你所有。")
            }
        }
        .navigationTitle("隐私说明")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 一条说明：标题 + 正文。
    private func item(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(body).font(.caption).foregroundColor(AppColor.ink2)
        }.padding(.vertical, 2)
    }
}
