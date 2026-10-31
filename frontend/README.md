# Frontend

这里是唯一的 Flutter 客户端工程根目录，未来覆盖 iOS、Android、Windows 和 macOS。

MVP 客户端直接访问设备本地 SQLite，不依赖后端。当前尚未初始化 Flutter 工程，也不包含业务代码。正式初始化后，工程内部将按 `lib/app/`、`lib/features/`、`lib/core/`、`lib/shared/`、`test/` 和 `assets/` 组织；详细职责见 `ForAI/Coder/技术选型.md`。

第二版如启用云端能力，客户端只能通过明确的 API 契约访问后端，绝不直接连接 PostgreSQL。
