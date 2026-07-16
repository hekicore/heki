# Heki

📚 文档: https://hekicore.github.io/heki-docs/

当前稳定版：`v1.2.2`。2026-07-16 同版本重发继续收口限速实现：除了修复用户/节点双限速在同一条连接上重复串行等待、导致 `100Mbps` 实际测速常落到约 `50Mbps`，现在还统一改成十进制 Mbps 口径并移除 idle burst，XBoard 后台与 Fast.com 一类测速不再出现 `10Mbps` 实际约 `13Mbps`、`100Mbps` 实际约 `130Mbps`。同一轮里 `Mieru UDP` 也兼容了 `proxy_protocol=true` 的旧/通用写法；本轮没有修改既有 SS / Shadow-TLS / SS2022 / TUIC / Hysteria2 on-wire 协议语义。
