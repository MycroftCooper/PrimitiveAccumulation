# 原始积累客户端

Flutter / Dart 的手机优先应用。Android、iOS、Windows 与 macOS 共用业务代码。首次启动可创建本机密码账本，或进入临时示例账本体验。个人账本从空数据开始。

## 运行

在本目录执行：

```sh
flutter pub get
flutter run
```

开发基线为 Flutter 3.44.8、Dart 3.12.2。使用 `flutter analyze` 和 `flutter test` 检查代码与关键流程。Android 调试包使用 `flutter build apk --debug` 构建。iOS 和 macOS 构建需要配备 Xcode 的 Mac。

## 页面和数据

- 成长页根据净资产绘制存钱罐，支持轻摇、切换上期与本期、编辑目标，以及从趋势和雷达图查原账。
- 账本支持按期及按条目查询。条目图表可在余额走势与构成占比之间切换，每次显示一张。
- 盘点时以最近一期为基础连续填表，保存的草稿可恢复。核对后原子提交完整快照；回执的备注可单独编辑，在回顾页查阅。
- 个人账本使用 SQLite3MultipleCiphers，由本机账本密码解锁。密码由用户保管。示例使用独立内存数据库，退出即清空。

## 设置与备份

首页右上角打开「设置」。进入「外观偏好」可切换主题与明暗模式。

个人账本可在「修改账本密码」中先验证旧密码，再输入两次新密码。保存后，下次解锁使用新密码。已导出的备份继续使用导出时设置的备份密码。

在支持的 Android 9 及以上手机或 iPhone 上，可在个人账本的「设置」开启「生物识别解锁」。输入当前账本密码并完成系统验证后，下次在锁屏页点「生物识别解锁」即可使用指纹或面容。更改账本密码或重新录入指纹、面容后，请用账本密码解锁并重新开启。

「导出备份」会将所有盘点明细、回顾备注、未提交草稿、目标和偏好保存为单个 `.pabackup` 文件。文件使用独立备份密码加密。请保管好密码，丢失后无法恢复备份。新设备上先创建个人账本，再进入「从文件恢复」。预览后确认会整体替换当前账本；本机解锁密码仍然有效。系统文件选择器触发应用锁后，解锁即可继续。

v1 文件依次包含 ASCII 标头 `PA-BACKUP:1\n`（末尾为换行）、16 字节随机盐、12 字节 nonce、加密的 UTF-8 JSON 和 16 字节认证标签。密钥使用 PBKDF2-HMAC-SHA256（600,000 轮）派生，加密使用 AES-256-GCM，标头参与认证。单文件上限为 32 MiB。iOS 文件选择器要求 iOS 14 或更新版本。

「检查更新」按需查询本项目的 GitHub Releases，只发送版本查询请求。正式发布使用与客户端版本对应的标签（例如 v0.2.0 或 v0.2.0+2），发现新版本时可打开发布页。

### Android 正式发布

版本名与构建号在 `pubspec.yaml` 中维护。首次正式版为 `0.0.1+5002`，构建号高于早期按 ABI 分包的本机试用版。运行 `flutter build apk --release` 生成通用 APK。正式包使用专用签名密钥。

Gradle 默认从 `~/.android/primitive-accumulation/key.properties` 读取 `storeFile`、`storePassword`、`keyAlias` 和 `keyPassword`。可以用 `PA_ANDROID_SIGNING_PROPERTIES` 指定其他位置，密钥库相对路径从该配置文件所在目录解析。请私下备份密钥库与配置，后续发布使用同一签名。

### 本地 CI 发布 Android 和 iOS

从仓库根目录运行一条命令。Mac 使用 `python3 scripts/release.py`，Windows 使用 `python scripts/release.py`。脚本从当前 Git 提交提取客户端，在临时目录依次安装锁定依赖、静态检查、运行所有 Flutter 测试、打签名 APK 和 Ad Hoc IPA，最后将两个附件发布到本项目的 GitHub Release。

**首次配置**

- 构建机准备 Python 3.9+、Git 与 Git LFS、Flutter 3.44.8、JDK 和 Android SDK，设置 `ANDROID_HOME` 并安装 SDK Build Tools。使用前述 Android 正式签名。多个 Flutter 并存时，可将 `PA_FLUTTER` 设为对应的 Flutter 可执行文件绝对路径。
- 发布机执行 `gh auth login` 和 `gh auth setup-git`，账号需要有本仓库推送标签和发布 Release 的权限。
- Mac 安装 Flutter 和 Xcode，完成 Xcode 首次初始化。在 Xcode 中登录 Apple 开发者账号，准备匹配 Runner Bundle ID `app.primitiveaccumulation.primitiveAccumulation` 的签名身份和 Ad Hoc 描述文件，并注册安装设备。在 Mac 的 `~/.config/primitive-accumulation/ios.xcconfig` 写入一行 `DEVELOPMENT_TEAM = 你的团队ID`。证书私钥保存在 Mac 钥匙串。Ad Hoc IPA 仅供描述文件中登记的设备安装；随 IPA 分发的描述文件包含这些设备的标识。
- 从 Windows 发起时，在 OpenSSH 中配置 Mac 的主机别名、密钥登录和已验证的主机密钥。PowerShell 中设置 `$env:PA_MAC_HOST = '你的Mac别名'`。Mac 的 Bash 登录环境应能找到 Flutter 和 Xcode，并能使用签名钥匙串。Android 构建和 GitHub 发布均在 Windows 上执行，仅将本次提交的客户端源码和 iOS 构建脚本传至 Mac。

**每次发布**

更新 `frontend/pubspec.yaml` 的版本名和构建号并提交本次改动，再运行入口。版本 `0.0.2+5003` 对应标签 `v0.0.2`。每个正式版本使用新标签。脚本验证 APK 的正式证书和版本、IPA 的签名和版本，产物位于 `frontend/build/releases/<标签>/<提交前12位>/`。

两个包就绪后，脚本推送指向同一提交的标签，并在 GitHub 草稿中上传、核对附件，最后公开 Release。打包失败时可修复环境后重跑。若上传中断，重跑同一提交可继续同名草稿。已经公开的版本使用新版本号发布更新。

## 主题和组件

- `lib/core/theme.dart` 集中提供皮肤配色、明暗背景、Material 组件样式，以及存钱罐和图表使用的语义颜色。新增配色从 `Skin` 扩展。
- `lib/shared/widgets.dart` 提供页面容器、面板、选择器、分段切换、明细行与空状态。
- `lib/shared/charts.dart` 中的图表通过数据和点击回调连接页面。`pig_bank.dart` 单独负责金币映射、绘制和减少动态效果适配。
- `lib/core/book.dart` 负责加密存储、盘点事务与偏好。`lib/features/` 负责用户流程，`lib/app/` 负责入口、应用锁与导航。
