# Heki

📚 文档: https://hekicore.github.io/heki-docs/

当前稳定版：`v1.3.0`；发布日期：`2026-11-14`。支持 Linux amd64 / arm64。

- **主副配置**：用户覆盖与启动快照分离，新增最终值及来源查看、配置诊断、停用节点配置保留；旧 AUTO+USER 文件成功启动后自动迁移。
- **功能**：新增用户态 WireGuard 出站、按地址族绑定出口、面板路由/DNS 刷新、SS UoT v1/v2、VMess/VLESS WebSocket early data、Hysteria2 ECH 和 PPanel 设备准入。
- **兼容与修复**：凭据改变后撤销旧连接，修正 MPTCP 开关，补回 AnyTLS 大帧与关闭期限、Vision 分块、QUIC stream 关闭等官方修复。
- **依赖与性能**：Xray 更新至 v26.11.9，更新 Reality、KCP、smux 等 9 项依赖；优化 GeoData、VMess 认证与防重放内存、SS2022 UDP 和审计关闭时的开销。

升级前备份完整实例配置目录（包括主配置、节点副配置、证书、路由与 DNS 文件）。1.3.0 没有自动配置备份；回退 1.2.9 时应恢复升级前配置，不能把只切换二进制视为无损回退。详见 [升级与回退](https://hekicore.github.io/heki-docs/#/other/upgrade-rollback)。

安装脚本用户执行 `heki update 1.3.0`；Docker 使用 `hekicore/heki:1.3.0` 或 `latest`，执行 `docker compose pull` 和 `docker compose up -d` 获取镜像并重建容器。仅重启旧容器不会更新程序。可使用 Release 附件 `SHA256SUMS` 核验安装包。

VMess AEAD 订阅建议删除 `alterId` 字段；旧客户端使用 MD5 时显式下发 `alterId>0` 并按需设置 `force_vmess_md5`。Heki 保留面板显式 alterId 优先及原认证兼容规则。

XBoard 默认 XHTTP 模板的字符串范围、布尔字符串、headers 数组和不完整 downloadSettings 占位已兼容。VMess/VLESS/Trojan 支持面板下发；AnyTLS 运行时支持 XHTTP，但仍取决于面板是否下发完整 network/networkSettings。XiaoV2Board v2node 兼容与原 SS/SS2022 加密及帧格式保持不变。

[完整发布说明](https://github.com/hekicore/heki/releases/tag/v1.3.0) · [主副配置及示例](https://hekicore.github.io/heki-docs/#/heki/heki-config)
