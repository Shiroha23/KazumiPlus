<div align="center">

<img src="assets/images/logo/logo_rounded.png" alt="KazumiPlus 图标" width="160">

# KazumiPlus

基于 Kazumi 的番剧客户端，持续打磨界面、桌面体验与规则扩展能力。

[![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-0175C2?logo=dart&logoColor=white)](https://dart.dev/)
[![License](https://img.shields.io/badge/License-GPL--3.0-blue)](LICENSE)

[下载](https://github.com/Shiroha23/KazumiPlus/releases) · [反馈问题](https://github.com/Shiroha23/KazumiPlus/issues) · [上游项目](https://github.com/Predidit/Kazumi) · [网站弹幕规则](static/doc/DANMAKU_RULES.md)

</div>

## 关于项目

KazumiPlus 是 [Kazumi](https://github.com/Predidit/Kazumi) 的衍生分支，使用 Flutter 开发，保留基于自定义规则的番剧检索、播放、弹幕、下载与同步能力，并在此基础上调整界面与交互，扩展视频源的适配方式。

本分支独立维护，功能与发布节奏可能与上游不同。感谢 Kazumi 作者与所有贡献者提供的基础。

## KazumiPlus 的改进

- **界面与交互**：统一热门与搜索页面的海报网格，调整热门页顶栏，改善各页面滚动体验、窗口缩放时的图片复用与桌面窗口启动显示。
- **桌面窗口材质**：Windows 支持亚克力、Mica、Mica Alt 和透明效果，macOS 支持原生毛玻璃；可调节背景浓度，并随主题切换与全屏退出恢复效果。可用选项取决于系统版本。
- **视频源网站登录**：可在应用内打开视频源网站完成登录，保存并复用登录状态；支持从规则管理、视频源检索及播放失败页面进入。
- **可配置的网站弹幕**：规则编辑器支持 JSON、DPlayer 与 Bilibili XML 格式，支持预请求提取分集 ID、字段映射、播放页测试，以及随视频下载缓存弹幕。配置可随规则导入、导出和分享，详见[网站弹幕规则](static/doc/DANMAKU_RULES.md)。

## 主要功能

| 类别 | 功能 |
| --- | --- |
| 番剧发现 | 热门番剧、搜索与筛选、时间表、详情与评论、图片识别番剧 |
| 自定义规则 | XPath 与 API 规则、规则编辑与测试、导入导出、规则仓库、多视频源切换 |
| 视频播放 | 硬件解码、倍速、字幕、播放进度记录、截图与导出、外部播放器 |
| 弹幕 | 弹弹play、网站弹幕、屏蔽规则、时间偏移、简繁转换 |
| 下载 | 分集下载、下载管理、离线播放、弹幕缓存 |
| 收藏与同步 | 本地追番与历史记录、Bangumi 收藏同步、WebDAV 收藏／历史／弹幕屏蔽规则同步 |
| 一起观看 | DLNA 投屏、基于 Syncplay 的一起看 |
| 画面与外观 | Anime4K 实时超分辨率、深浅色主题、动态配色、桌面窗口材质 |
| 网络设置 | 番剧条目镜像／ECH／直连、图片加速、规则仓库镜像、代理配置 |

具体能力受平台、设备性能和视频源支持情况影响。

## 下载与平台

请从 **[KazumiPlus Releases](https://github.com/Shiroha23/KazumiPlus/releases)** 获取本分支发布的安装包，可用平台与架构以实际发布附件为准。没有对应安装包时，可参考下方说明从源码构建。

项目沿用 Kazumi 的跨平台工程：

| 平台 | 基础要求与说明 |
| --- | --- |
| Android | Android 10 及以上 |
| Windows | Windows 10 及以上；窗口材质按系统版本提供 |
| macOS | macOS 10.15 及以上 |
| Linux | 实验性支持，运行依赖与桌面集成因发行版而异 |
| iOS | iOS 13 及以上，需要自行签名或侧载 |

上表沿用上游标注的系统基线，不代表本分支已在所有平台完成验证；实际兼容性以构建产物和设备测试为准。

应用内更新从本仓库 GitHub Releases 检查和下载。上游的 F-Droid、Flathub、AUR 等渠道分发的是 Kazumi。

Windows ZIP 可解压运行。发布流程未配置本分支的签名服务时，MSIX 产物未签名，需要自行签名后安装。

## 开始使用

1. 首次启动时完成引导，根据网络情况选择访问加速方式。
2. 在引导页添加番剧来源，或进入「规则管理」从规则仓库安装、导入或自行编写规则。项目不再内置默认规则，播放前需要至少一条可用规则。
3. 搜索或浏览番剧，打开详情页，选择视频源、线路和集数开始播放。
4. 按需配置弹幕、下载、追番与同步；需要跨设备同步时，在同步设置中连接 Bangumi 或 WebDAV。

规则仅描述第三方站点的检索与解析方式。规则失效时，可先更新规则，再检查来源站点是否可正常访问。

## 常见问题

<details>
<summary>如何开启窗口毛玻璃或 Mica？</summary>

在「设置 → 外观设置 → 窗口」中选择「窗口效果」，可同时调节背景浓度。此功能默认关闭，Windows 按系统版本显示可用选项，macOS 提供原生毛玻璃。

</details>

<details>
<summary>视频源需要登录后才能播放怎么办？</summary>

在规则管理中打开对应规则的更多菜单，选择「网站登录」，完成登录后点击「保存并返回」。也可以从视频源检索菜单或播放失败页面进入，返回后会自动重试。

如网站提供「记住登录」选项，可勾选以便下次使用。登录有效期由网站决定；退出账号需要重新进入「网站登录」并在网站内操作。

</details>

<details>
<summary>如何使用网站自带的弹幕？</summary>

在「规则编辑器 → 弹幕」中按来源网站的实际接口填写配置，并使用播放页地址测试。配置方法和示例见[网站弹幕规则](static/doc/DANMAKU_RULES.md)。

未启用网站弹幕配置的规则使用弹弹play。启用后，空列表表示该集暂无网站弹幕，请求或解析失败会报告规则错误。开启「下载弹幕」后，网站弹幕也会缓存以供离线播放。

</details>

<details>
<summary>封面或番剧信息加载失败怎么办？</summary>

在「设置 → 网络设置」中调整「番剧条目加速」「图片加速」或「规则仓库镜像」，也可按需配置代理。这些选项用于不同类型的请求，视频能否播放还取决于所选来源网站。

</details>

<details>
<summary>开启超分辨率后卡顿，或播放时内存占用较高？</summary>

Anime4K 对 GPU 性能有一定要求，可尝试效率档、用于较低分辨率的视频，或关闭超分辨率。播放缓存会占用内存，内存紧张时可在播放设置中调整低内存模式。

</details>

<details>
<summary>为什么视频中有广告，或外部播放器无法播放？</summary>

视频中的广告可能来自来源站点，可尝试切换视频源。部分来源需要特定请求头、Cookie 或其他播放条件，外部播放器未必能够复用这些信息。

</details>

## 从源码构建

Flutter 版本以 [pubspec.yaml](pubspec.yaml) 中的 `environment.flutter` 为准，当前为 **3.47.7**，Dart SDK 约束为 `>=3.10.0 <4.0.0`。还需安装目标平台的开发工具链，并确保可以获取 Flutter、pub.dev、GitHub 和相关原生依赖。

```bash
git clone https://github.com/Shiroha23/KazumiPlus.git
cd KazumiPlus

flutter doctor -v
flutter pub get
flutter run
```

### 弹幕凭据

自行构建时，弹弹play在线弹幕需要为自己的应用申请 AppId 和 AppSecret。复制根目录的凭据模板，例如在 PowerShell 中执行：

```powershell
Copy-Item .kazumi_build_defines.env.example .kazumi_build_defines.env
```

在 `.kazumi_build_defines.env` 中填写 `DANDANAPI_APPID` 和 `DANDANAPI_KEY`，然后运行：

```bash
flutter run --dart-define-from-file=.kazumi_build_defines.env
```

未配置时，弹弹play弹幕加载与手动检索不可用，已配置的网站弹幕规则不受影响。可选的 `KAZUMI_APPID`、`KAZUMI_KEY` 用于 Kazumi 镜像凭据；留空时搜索使用官方接口。

本地凭据文件已加入 `.gitignore`，请勿提交凭据。修改后需要停止应用并重新运行。

### 检查与打包

```bash
flutter test
flutter analyze --no-fatal-infos --fatal-warnings

# 按目标平台选择命令，在对应系统与工具链下执行
flutter build apk --release --dart-define-from-file=.kazumi_build_defines.env
flutter build windows --release --dart-define-from-file=.kazumi_build_defines.env
flutter build macos --release --dart-define-from-file=.kazumi_build_defines.env
flutter build linux --release --dart-define-from-file=.kazumi_build_defines.env
flutter build ios --release --no-codesign --dart-define-from-file=.kazumi_build_defines.env
```

未签名的 iOS 构建产物仍需签名后才能安装。更多开发约定见[贡献指引](static/doc/CONTRIBUTING.md)，代码组织见[项目结构](static/doc/STRUCTURE.md)。

## 反馈与贡献

欢迎在 [Issues](https://github.com/Shiroha23/KazumiPlus/issues) 中提交问题与建议，或通过 Pull Request 参与改进。反馈时请附上系统与应用版本、复现步骤，以及必要的截图或脱敏日志。

编写网站弹幕配置请参考[本地文档](static/doc/DANMAKU_RULES.md)。通用规则可参考上游 [KazumiRules](https://github.com/Predidit/KazumiRules)；本分支扩展字段的兼容性取决于接收端的规则 API 版本。

## 许可证与资源归属

代码沿用 [GNU GPL v3](LICENSE) 许可证，使用、修改和分发时请遵守许可证要求。软件按许可证约定提供，不作适用性或可靠性保证。

- **图标**：来自 [Yuquanaaa](https://www.pixiv.net/users/66219277) 的 [Pixiv 作品](https://www.pixiv.net/artworks/116666979)。原项目声明已获得作者使用授权；图标版权仍属于原作者，不属于可随意使用的自由素材，使用、复制、修改或分发需取得相应授权。
- **字体**：内嵌 MiSans 字体由 Xiaomi 开发，字体使用须遵循其自身授权条款。
- **第三方组件**：各自遵循对应许可证；ECH 原生依赖声明见 [THIRD_PARTY_NOTICES](licenses/ech_http/THIRD_PARTY_NOTICES.md)，着色器许可见 [assets/shaders/LICENSE](assets/shaders/LICENSE)。

番剧元数据、弹幕与视频内容来自相应第三方服务或用户配置的来源站点，相关内容权利归各自权利人所有。

## 隐私

项目不使用遥测组件。设置、收藏、历史记录及网站登录状态会保存在本地；启用 Bangumi 或 WebDAV 同步时，相应数据会发送至所连接的服务。检索、播放、弹幕、图片识别与更新检查等联网功能会请求对应第三方服务。

## 致谢

- [Kazumi](https://github.com/Predidit/Kazumi) 及其[贡献者](https://github.com/Predidit/Kazumi/graphs/contributors)：本项目的上游与基础。
- [Bangumi](https://bangumi.tv/)：番剧元数据与收藏服务。
- [弹弹play](https://www.dandanplay.com/)：开放弹幕服务。
- [XpathSelector](https://github.com/simonkimi/xpath_selector)：XPath 规则解析。
- [media-kit](https://github.com/media-kit/media-kit) 与 [avbuild](https://github.com/wang-bin/avbuild)：跨平台媒体播放及相关底层支持。
- [Anime4K](https://github.com/bloc97/Anime4K)：实时超分辨率。
- [Syncplay](https://github.com/Syncplay/syncplay)：一起看协议与公共服务器。
- [trace.moe](https://trace.moe/)：图片识别番剧。
- [Hive](https://github.com/isar/hive) 与 [Hive CE](https://github.com/IO-Design-Team/hive_ce)：本地数据存储。

感谢所有为 Kazumi 与 KazumiPlus 提供代码、规则、反馈和资源的贡献者。
