# Heki

📚 文档: https://hekicore.github.io/heki-docs/

当前稳定版：`v1.2.9`；发布日期：`2026-10-31`

最新同版本重发：修复 XHTTP HTTP/3 活跃会话导致停止卡住的问题，补齐连接、上传队列及 UDP 端口回收，无需修改配置。[XHTTP 配置与说明](https://hekicore.github.io/heki-docs/#/other/xhttp-config)。

2026-10-31 再次同版本重发：新增 Hy2 HTTP/3 网站伪装，`hysteria_masquerade` 支持反向代理、静态目录、固定响应，默认关闭；支持环境变量和节点独立覆盖。[配置实例与使用限制](https://hekicore.github.io/heki-docs/#/hysteria/masquerade)。

2026-10-31 同版本重发：新增远程 DNS 定时更新（`dns_rules_url`、`dns_rules_update_interval`）、BT 过滤增强和 ClickHouse gzip（`access_log_clickhouse_gzip`，默认关闭），修复 TUIC 首包缓存并发释放。BT 检测不依赖常见端口，但不能保证封锁加密 BT。

旧版 1.2.9 用户也需执行 `heki update 1.2.9`，或执行 `docker compose pull && docker compose up -d` 拉取镜像并重建容器。版本号不变，可使用 Release 附件 `SHA256SUMS` 核验安装包。

- 修复 VLESS + Reality/TLS + TCP + Vision 的 UDP（Mux/XUDP）转发
- XiaoV2Board 支持 Hy2 自签证书下发和 SHA-256 pin 校验；PPanel 自签模式上报实际证书指纹，并兼容新版响应字段
- Mieru 升级至 3.39.0，握手、空连接与 TCP 无流量超时默认均关闭，可通过 `mieru_handshake_timeout`、`mieru_empty_timeout`、`mieru_tcp_idle_timeout` 自行设置；6 分 30 秒是空连接复用宽限，不是连接数
- 升级 Hysteria 2.13.0、Xray 26.10.29、sing 0.9.6、sing-quic 0.7.1、Reality、Shadowsocks 等依赖并保留本地补丁；Naive 补齐官方 Padding 协商
- 授权检查与缓存容灾加固，保留原授权签名协议和旧缓存供回滚；正式包默认选择性混淆授权包，协议转发路径不新增逐包/逐连接联网或验签
- SSPanel-UIM、XBoard、XiaoV2Board、PPanel 的 11 个选定真实联调案例通过，不代表穷举所有组合

升级前请注意：XHTTP 下载端的 `allowInsecure=true` 必须迁移为可信证书或 pin；PPanel 自签 Hy2 默认订阅模板遗漏 pin，需要按文档迁移。在线授权节点应保持系统时间准确并保留缓存，建议先小批量滚动升级。

[完整发布说明](https://github.com/hekicore/heki/releases/tag/v1.2.9)
