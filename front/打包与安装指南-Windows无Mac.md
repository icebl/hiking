# 在 Windows（无 Mac）下打包并安装到 iPhone

> 思路：**云端 macOS（GitHub Actions）编译出未签名 .ipa → 在 Windows 用 Sideloadly 重签安装到 iPhone**。
> 全程不需要自有 Mac，免费 Apple ID 即可（装上的 App **7 天有效**，到期重装即可）。

---

## 前置

- 一个 **GitHub 账号**（免费）。
- 一个 **Apple ID**（免费即可；开了两步验证的话需生成 App 专用密码）。
- iPhone 一台 + 数据线。
- Windows 上装 **iTunes**（提供驱动）+ **Sideloadly**（https://sideloadly.io）。

---

## 第 1 步：把项目推到 GitHub

```bash
cd d:/Project/AI/hiking
git init
git add .
git commit -m "init: hiking app scaffold"
# 在 GitHub 新建一个空仓库，然后：
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git branch -M main
git push -u origin main
```

> 仓库可设为 Private。CI 配置已在 `.github/workflows/ios-build.yml`。

## 第 2 步：云端编译出 .ipa

- 推送后，GitHub 仓库 **Actions** 标签页会自动运行 “iOS Build (unsigned IPA)”。
- 也可在 Actions 页点 **Run workflow** 手动触发。
- 跑完后进入该次运行，在底部 **Artifacts** 下载 `Hiking-unsigned-ipa`（解压得到 `Hiking-unsigned.ipa`）。

> ⚠️ 当前是脚手架代码，**首次编译很可能报 Swift 编译错误**（我写的是未在 Xcode 编过的骨架）。把 Actions 的报错日志发我，我来逐个修，直到绿灯出包。

## 第 3 步：用 Sideloadly 装到 iPhone

1. iPhone 连电脑，iTunes 能识别即可（不用打开）。
2. 打开 **Sideloadly**，把 `Hiking-unsigned.ipa` 拖进去。
3. 填你的 **Apple ID**，点 **Start**；首次会用你的 Apple ID 生成免费开发证书并重签安装。
4. iPhone 上：**设置 → 通用 → VPN与设备管理 → 信任你的 Apple ID 开发者证书**。
5. 回到桌面打开 App。

> **7 天后会闪退/失效**：重新用 Sideloadly 装一次即可（免费 ID 的限制）。
> 想免去 7 天限制、或用 TestFlight 分发给别人 → 需要 **$99/年 Apple 开发者账号**。

---

## 重要预期

1. **能装 ≠ 能测徒步功能**。现在装上只是空壳（4 个 Tab、空地图、空列表）。要真正测记录/导航/等高线，需要先把 `MVP开发任务清单.md` 的 S1（数据层）、S3（记录）、S2（地图 style/离线）填实。
2. **后台定位、气压计** 这类只能**真机**测，模拟器测不了 —— 这条 Windows+Sideloadly 路线正好能上真机。
3. 地图要显示内容，还需要准备 **底图 style + PMTiles 瓦片**（S2.9 的数据管线，可在 Windows/服务器跑）。

---

## 路线图建议（无 Mac 场景）

1. 先跑通 CI（绿灯出包）→ 装个空壳验证装机链路通。
2. 并行：在 Windows 做**离线地图数据管线**（planetiler + GDAL + tippecanoe → PMTiles），与 iOS 编译无关。
3. 逐个 Sprint 填实，每次推送 CI 自动出新包，Sideloadly 重装即可看到进展。
