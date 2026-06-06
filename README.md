# Heki

📚 文档: https://hekicore.github.io/heki-docs/

当前稳定版：`v1.2.1`（2026-06-06 同版本重发）。本次重发同步 Hysteria2 上游 core/extras 到 `v2.9.2`，并修复 XBoard / heki-v1 单用户节点里唯一用户过期后再续费仍需重启 heki 才能恢复的 ETag 缓存问题；同时新增内存与 pprof 排查文档。此前 `1.2.1` 的 SS2022 deadline 刷新节流、HTTP 代理 sniff route target 修复、Mieru 多用户握手优化、Redis 在线 IP 上报削峰、Xiao / V2Board 在线 IP 精确清理、`dns.yml` 启动兼容、Shadowsocks 现代 AEAD cipher 扩展、SSPanel Trojan `insecure=1` 解析兼容，以及 Mieru 直连目标失败日志刷屏收口继续保留。
