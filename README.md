# 复古电台 Retro Radio

一个自用的 iPhone 网络电台 App，界面仿老式收音机（参考 App Store 上的 “Radio Anywhere”），基于开源项目 [Swift Radio Pro](https://github.com/analogcode/Swift-Radio-Pro)（MIT 许可）改造。

## 功能

- **一点就响**：从主屏幕点开 App，自动继续播放上次收听的电台；第一次打开播放列表里的第一个电台。（可在“我的电台 → 设置”里关闭。）
- **复古界面**：暖色背光刻度盘 + 红色指针，琥珀色显示屏显示电台名和正在播放的曲目；转动旋钮调台（有触感反馈），也可以直接点刻度盘。
- **6 个预设键**：轻点播放，长按把当前电台存到这个键。
- **我的电台**：手动添加（名称 + 流地址）、编辑、删除、拖动排序；旋钮按这个顺序调台。
- **电台库搜索**：使用免费的 [Radio Browser](https://www.radio-browser.info) 电台库，按名称 / 国家地区 / 标签搜索，一键“只看中文电台”，轻点试听，点 + 加入我的电台。
- **Siri / 快捷指令**：“播放电台”动作，打开 App 并播放上次的电台。可以对 Siri 说“用复古电台播放电台”，或在“快捷指令”App 里添加。
- **后台播放**，锁屏和控制中心可以暂停 / 切台。

内置电台：KEXP、KCRW、NPR、BBC World Service、中国之声、香港电台普通话台、RFI 法广华语等。

## 下载安装（不需要 Mac）

每次推送到 `main` 分支，GitHub Actions 会自动编译一个**未签名**的 `RetroRadio.ipa`，并发布到本仓库的 **Releases** 页面。

1. 打开本仓库的 **Releases**，下载最新的 `RetroRadio.ipa`（手机或电脑都可以下载）。
2. 在 Windows 或 Mac 电脑上用以下任一工具，登录你的**免费 Apple ID** 进行自签并安装到 iPhone：
   - **Sideloadly**（推荐，Windows / Mac）：把 IPA 拖进去，填 Apple ID，点 Start。
   - **AltStore**（需在电脑上运行 AltServer）。
   - **爱思助手**：工具箱 → IPA 签名，用 Apple ID 签名后安装。
3. 第一次安装后，在 iPhone 上打开 **设置 → 通用 → VPN 与设备管理**，信任你的 Apple ID 开发者证书。
4. iOS 16 及以上需要打开 **设置 → 隐私与安全性 → 开发者模式**（按提示重启）。

### 注意

- 免费 Apple ID 签名的 App **7 天后会失效**，需要用同样的工具重新签名安装（数据会保留）。AltStore 可以在同一 Wi-Fi 下自动续签。
- 免费 Apple ID 最多同时安装 3 个自签 App。
- App 的 Bundle ID 是 `one.lxc.retroradio`（小组件是 `one.lxc.retroradio.widget`）。为了能用免费 Apple ID 签名，已去掉 CarPlay 等需要付费开发者账号的功能。

## 自己编译

- 需要 Xcode 26（iOS 17 及以上）。用 Xcode 打开 `SwiftRadio.xcodeproj`，选择 `SwiftRadio` scheme 运行即可。
- CI 配置在 `.github/workflows/build-ipa.yml`。如果 `macos-26` 运行器不可用，可以在仓库 Settings → Secrets and variables → Actions → Variables 里新建变量 `MACOS_RUNNER=macos-latest`（以及可选的 `XCODE_VERSION`）。

## 代码结构

- `SwiftRadio/Retro/`：复古界面、预设、我的电台、电台库搜索、Siri 动作。
- `Packages/SwiftRadioCore/`：原项目的播放核心（PlayerService、StationsStore），未改动。
- `SwiftRadio/Data/stations.json`：首次启动时的默认电台列表。

## 许可

MIT，见 [LICENSE](LICENSE)。原项目版权归 Swift Radio Pro 作者所有。
