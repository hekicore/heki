# Heki

高性能多协议代理服务端，支持 VMess / VLESS / Trojan / Shadowsocks / ShadowsocksR / Hysteria2 / AnyTLS / Naive / Mieru。

支持对接 SSPanel-UIM / V2Board / XBoard 面板。

## 安装

### 一键安装

```bash
bash <(curl -Ls https://raw.githubusercontent.com/hekicore/heki/master/install.sh)
```

安装后使用 `heki` 命令管理：

```bash
heki              # 交互式管理菜单
heki setup        # 配置引导（首次配置推荐）
heki status       # 查看状态
heki log          # 查看日志
```

### Docker 部署

**单节点：**

```bash
docker run --restart=on-failure --name heki -d \
  -v /etc/heki/:/etc/heki/ --network host \
  -e type=sspanel-uim \
  -e panel_url=https://your-panel.com \
  -e panel_key=your-api-key \
  -e node_id=1 \
  -e heki_key=your-heki-license-key \
  hekicore/heki
```

**多节点（一个容器运行多个节点）：**

```bash
docker run --restart=on-failure --name heki -d \
  -v /etc/heki/:/etc/heki/ --network host \
  -e type=xboard \
  -e panel_url=https://your-panel.com \
  -e panel_key=your-api-key \
  -e node_id="1,2,3" \
  -e heki_key=your-heki-license-key \
  hekicore/heki
```

**使用 docker-compose：**

```bash
mkdir -p /etc/heki && cd /etc/heki
curl -sL https://raw.githubusercontent.com/hekicore/heki/master/docker-compose.yml -o docker-compose.yml
# 编辑 docker-compose.yml 填入你的配置
docker compose up -d
```

## 管理命令

安装后使用 `heki` 命令管理：

```bash
heki                # 交互式管理菜单
heki setup          # 配置引导（首次配置推荐）
heki start          # 启动
heki stop           # 停止
heki restart        # 重启
heki status         # 查看状态
heki log            # 查看日志
heki config         # 查看配置
heki modify         # 修改配置
heki node list      # 查看节点列表
heki node add 2     # 添加节点
heki node del 2     # 删除节点
heki cert           # 证书管理
heki reality gen    # 生成 Reality 密钥对
heki update         # 更新到最新版
heki update x.x.x   # 更新到指定版本
heki uninstall      # 卸载
```

## 多节点部署

Heki 支持单进程运行多个节点：

```bash
# 配置文件方式
node_id=1,2,3

# 环境变量方式（Docker）
-e node_id="1,2,3"

# 命令行管理
heki node add 2     # 添加节点 2
heki node del 2     # 删除节点 2
heki node list      # 查看所有节点
```

## 支持的协议

| 协议 | 传输层 |
|------|--------|
| VMess | TCP / WebSocket / H2 / gRPC |
| VLESS | TCP / WebSocket / H2 / gRPC / Reality |
| Trojan | TCP / WebSocket / H2 / gRPC |
| Shadowsocks | TCP / UDP（2022 / AEAD / Stream） |
| ShadowsocksR | TCP / UDP |
| Hysteria2 | QUIC |
| AnyTLS | TLS |
| Naive | HTTP CONNECT over TLS |
| Mieru | TCP / UDP（XChaCha20-Poly1305）|

## 支持的面板

- SSPanel-UIM
- V2Board（原版）
- XBoard
- XiaoV2Board（wyx2685 分支）

## 必需配置项

| 配置项 | 说明 | 示例 |
|--------|------|------|
| `type` | 面板类型 | `sspanel-uim` / `xboard` / `v2board` / `xiaov2board` |
| `panel_url` | 面板地址 | `https://your-panel.com` |
| `panel_key` | 面板通信密钥 | `your-api-key` |
| `node_id` | 节点 ID（支持多节点） | `1` 或 `1,2,3` |
| `heki_key` | Heki 授权码 | `your-heki-license-key` |

## 配置示例

参考 [heki.conf.example](heki.conf.example)

## 文档

详细文档请访问：[heki-docs](https://hekicore.github.io/heki-docs/)

## Docker 镜像

```
docker pull hekicore/heki:latest
```

支持 `linux/amd64` 和 `linux/arm64` 双架构。
