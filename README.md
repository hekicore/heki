# Heki

📚 文档: https://hekicore.github.io/heki-docs/

当前稳定版：`v1.3.1`；发布日期：`2026-11-22`。支持 Linux amd64 / arm64。

- **XUDP 与 WS**：修复 VMess 同会话多目标 XUDP，新增可选 WS 主动心跳 `ws_heartbeat`，修复 VMess 大块下载和响应兼容。
- **流量上报**：批次持久化、重启恢复；旧面板结果不明时保留未确认量，自动继续后续上报，无需人工解锁。不确定批次可能少计，优先避免重复扣量。
- **协议与兼容**：改进 SS UDP 异步建连及出口检查、TUIC 大 UDP 与用户撤销、AnyTLS 关闭、H2/gRPC 期限；保留 XBoard 与旧 XiaoV2Board API 回退。
- **更新与稳定性**：DNS/Geo 无效更新保留旧数据，完善设备限制、敏感日志、证书续期；安装失败回滚及程序自动更新验签。自动更新默认关闭，离线交付方式保持原样。

升级前备份完整实例配置目录和 Docker Compose/环境配置。流量状态需要可写且持久化的目录；只读配置挂载请另设 `ip_user_cache_save_dir`。详见 [流量上报](https://hekicore.github.io/heki-docs/#/other/traffic-accounting) 与 [升级回退](https://hekicore.github.io/heki-docs/#/other/upgrade-rollback)。

安装脚本用户执行 `heki update 1.3.1`；Docker 使用 `hekicore/heki:1.3.1` 或 `latest`，执行 `docker compose pull` 和 `docker compose up -d`。仅重启旧容器不会更新程序。Release 提供 `SHA256SUMS` 与新版程序自动更新所用的 `SHA256SUMS.sig`，客户无需配置签名私钥。

VMess AEAD 订阅建议删除 `alterId` 字段；旧客户端使用 MD5 时显式下发 `alterId>0` 并按需设置 `force_vmess_md5`。Heki 保留面板显式 alterId 优先及原认证兼容规则。

XBoard 默认 XHTTP 模板的字符串范围、布尔字符串、headers 数组和不完整 downloadSettings 占位已兼容。VMess/VLESS/Trojan 支持面板下发；AnyTLS 运行时支持 XHTTP，但仍取决于面板是否下发完整 network/networkSettings。XiaoV2Board v2node 兼容与原 SS/SS2022 加密及帧格式保持不变。

[完整发布说明](https://github.com/hekicore/heki/releases/tag/v1.3.1) · [主副配置及示例](https://hekicore.github.io/heki-docs/#/heki/heki-config)
