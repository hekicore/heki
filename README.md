# Heki

📚 文档: https://hekicore.github.io/heki-docs/

当前稳定版：`v1.2.5`；最近更新：`2026-09-04`

本次 1.2.5 同版本重发修复内置 `simple_obfs_http` / `simple_obfs_tls` 握手阻塞 Accept 循环导致的 SS 批量超时断流；默认配置无需增加参数，HTTP/TLS 协议格式已对齐官方 simple-obfs，并通过真实 Mihomo、多种 SS AEAD 和大包长流回归。同时保留 Hysteria2 唯一活跃 IP 统计修复与默认关闭的 ClickHouse 全量访问日志。
