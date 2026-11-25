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

## 主题和组件

- `lib/core/theme.dart` 集中提供皮肤配色、明暗背景、Material 组件样式，以及存钱罐和图表使用的语义颜色。新增配色从 `Skin` 扩展。
- `lib/shared/widgets.dart` 提供页面容器、面板、选择器、分段切换、明细行与空状态。
- `lib/shared/charts.dart` 中的图表通过数据和点击回调连接页面。`pig_bank.dart` 单独负责金币映射、绘制和减少动态效果适配。
- `lib/core/book.dart` 负责加密存储、盘点事务与偏好。`lib/features/` 负责用户流程，`lib/app/` 负责入口、应用锁与导航。
