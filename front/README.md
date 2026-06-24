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
