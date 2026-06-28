import SwiftUI

/// 关于页（发布收尾）：版本信息 + 底图/数据来源与版权署名 + 开源组件 + 隐私说明入口。
/// 署名为合规要求：ESRI 影像、OpenStreetMap/OpenMapTiles 矢量、Copernicus DEM、字体与各开源库都需标注。
struct AboutView: View {
    var body: some View {
        List {
            // 顶部：图标占位 + 名称 + 版本
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "mountain.2.fill").font(.system(size: 26))
                        .foregroundColor(.white).frame(width: 54, height: 54)
                        .background(AppColor.primary).clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("路迹").font(.system(size: 19, weight: .bold))
                        Text(Self.versionText).font(.caption).foregroundColor(AppColor.ink2)
                    }
                }.padding(.vertical, 4)
            }

            // 底图与数据来源（版权署名）
            Section("底图与数据来源") {
                attribution("在线影像", "© Esri、Maxar、Earthstar Geographics（World Imagery）")
                attribution("离线矢量底图", "© OpenStreetMap 贡献者 · OpenMapTiles，本地由 planetiler 生成")
                attribution("等高线", "Copernicus GLO-30 DEM（© ESA / Copernicus）")
                attribution("字体", "Open Sans（Apache License 2.0）")
            }

            // 开源组件（点进看许可证全文）
            Section("开源组件") {
                attribution("MapLibre Native", "BSD-2-Clause")
                attribution("GRDB.swift", "MIT License")
                attribution("CoreGPX", "MIT License")
                NavigationLink { LicensesView() } label: {
                    Label("查看许可证全文", systemImage: "doc.text")
                }
            }

            // 隐私说明 + 诊断日志入口
            Section {
                NavigationLink { PrivacyView() } label: {
                    Label("隐私说明", systemImage: "hand.raised")
                }
                NavigationLink { DiagnosticsView() } label: {
                    Label("诊断日志", systemImage: "waveform.path.ecg")
                }
            } footer: {
                Text("路迹为本地优先应用：轨迹、航点与照片均保存在本机，不上传服务器。")
            }
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 版本号：取 Bundle 的市场版本 + 构建号，缺失时回退占位。
    private static var versionText: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(v)（\(b)）"
    }

    /// 一条署名行：左标题，右（次要色）说明，长文本可换行。
    private func attribution(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 15, weight: .medium))
            Text(detail).font(.caption).foregroundColor(AppColor.ink2)
        }.padding(.vertical, 2)
    }
}
