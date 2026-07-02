# Heki

📚 文档: https://hekicore.github.io/heki-docs/

当前稳定版：`v1.2.2`。2026-07-02 同版本重发补齐 TUIC ECH keyset 接入、XBoard V2 合并 `/report` 上报，以及通用限速器 CPU 热点优化；现场 pprof 中旧版 `SpeedLimiter.WaitAndConsume/Consume` 约 `62.7%` 累计 CPU 的热点已移除。静态用户限速与动态限速现在按同一用户维度取最小值，节点级限速仍作为全局维度独立保留；既有 SS / Shadow-TLS / SS2022 / TUIC on-wire 协议语义保持不变。
