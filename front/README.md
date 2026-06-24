# Hiking App — iOS (front)

徒步 APP 的 iOS 客户端工程骨架。技术栈：Swift + SwiftUI / MapLibre Native / GRDB(SQLite) / CoreGPX / Core Location + CoreMotion。

> ⚠️ 需在 **macOS + Xcode** 上构建。此目录为可跨环境维护的源码 + XcodeGen 配置；Windows 上只编辑代码，编译在 Mac 进行。

## 目录结构

```
front/
├─ project.yml                 # XcodeGen 工程定义（生成 .xcodeproj）
├─ Sources/
│  ├─ App/                     # App 入口 + 根导航（4 Tab）
│  ├─ Core/
│  │  ├─ Models/               # Track/TrackPoint/Waypoint/RecordingSession (GRDB)
│  │  ├─ Database/             # AppDatabase + 迁移 + TrackRepository
│  │  ├─ Location/             # LocationManager（后台定位）
│  │  ├─ Sensors/              # AltimeterManager（气压计）
│  │  ├─ Map/                  # MapLibreView (UIViewRepresentable)
│  │  ├─ GPX/                  # GPXService（导入/导出）
│  │  ├─ Navigation/           # NavigationEngine（偏航/剩余里程）
│  │  └─ DesignSystem/         # 颜色/字体/尺寸 Token
│  └─ Features/
│     ├─ Home/  Map/  Tracks/  Recording/  Navigation/  Me/
└─ Resources/                  # Assets、Info 由 project.yml 注入
```

## 在 Mac 上首次运行

```bash
brew install xcodegen          # 若未安装
cd front
xcodegen generate              # 生成 Hiking.xcodeproj（解析 SPM 依赖）
open Hiking.xcodeproj
# 选择模拟器/真机运行（后台定位需真机验证）
```

## SPM 依赖（已在 project.yml 声明）

| 库 | 用途 | 仓库 |
|----|------|------|
| MapLibre | 地图引擎 | maplibre/maplibre-gl-native-distribution |
| GRDB | SQLite 本地库 | groue/GRDB.swift |
| CoreGPX | GPX 读写 | vincentneo/CoreGPX |

## 权限（project.yml 已注入 Info）

- 定位（When/Always）：记录与后台导航。
- 后台模式 `location`：徒步全程后台记录。
- 运动与健身 `NSMotionUsageDescription`：气压计海拔。

## 现状

骨架阶段：分层、导航、模型、各服务接口与 SwiftUI 页面占位均已就位，关键实现以 `// TODO(Sx.x)` 标注，对应 `需求文档/MVP开发任务清单.md` 的任务编号。


## 通过 GitHub Actions 自动构建 IPA 并使用 Sideloadly 侧载到 iPhone‌的完整流程。
第一步：推到GitHub（把代码上传到云端仓库）

git init → 在电脑的代码文件夹里初始化一个Git仓库（相当于在这个文件夹里开启“版本管理”功能）

提交 → 把当前写好的所有代码打包成一个“版本快照”，存到本地记录里

push到一个新仓库 → 把这个本地快照上传到你新建的GitHub远程仓库里（相当于备份到云端，并触发后续自动操作）

第二步：下载包（等待自动编译，然后下载安装包）

GitHub上有一个叫 Actions 的功能，它会自动检测到你刚push的代码，然后开始编译打包（这个过程不需要你手动操作）

等它跑完（绿色对勾表示成功），在页面的 Artifacts（编译产物）区域，找到并下载 Hiking-unsigned.ipa 文件
→ .ipa 就是iOS应用的安装包，unsigned表示它没有经过苹果官方签名（所以不能从App Store装，需要用第三方工具）

第三步：装机（把应用装到你的iPhone上）

Windows装Sideloadly → 在你的Windows电脑上下载并安装一个叫Sideloadly的第三方工具（它用来给未签名的ipa“注入”你的个人开发者签名）

拖入.ipa，填Apple ID → 打开Sideloadly，把刚才下载的.ipa文件拖进去，输入你的苹果账号和密码（用于向苹果申请临时签名）

装到iPhone → 点击开始，Sideloadly会把签名后的应用通过数据线安装到你的手机上

设置里信任证书 → 装完后，去iPhone的 设置 → 通用 → VPN与设备管理，找到对应的开发者证书，点击“信任”，然后就能正常打开这个App了


