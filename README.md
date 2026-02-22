# Heki

高性能多协议代理服务端，支持 VMess / VLESS / Trojan / Shadowsocks / ShadowsocksR / Hysteria2 / AnyTLS。

支持对接 SSPanel-UIM / V2Board / XBoard 面板。

## 安装

### 一键安装

```bash
bash <(curl -Ls https://raw.githubusercontent.com/hekicore/heki/master/install.sh)
```

### Docker 部署

```bash
docker run --restart=on-failure --name heki -d \
  -v /etc/heki/:/etc/heki/ --network host \
  -e type=sspanel-uim \
  -e node_id=1 \
  -e heki_key=xxx \
  -e webapi_url=https://xxx.com/ \
  -e webapi_key=xxxxxx \
  hekicore/heki
```

或使用 docker-compose：

```bash
mkdir -p /etc/heki && cd /etc/heki
curl -sL https://raw.githubusercontent.com/hekicore/heki/master/docker-compose.yml -o docker-compose.yml
# 编辑 docker-compose.yml 填入你的配置
docker compose up -d
```

## 管理命令

安装后使用 `heki` 命令管理：

```
heki                - 显示管理菜单
heki start          - 启动
heki stop           - 停止
heki restart        - 重启
heki status         - 查看状态
heki log            - 查看日志
heki update         - 更新
heki update x.x.x   - 更新到指定版本
heki config         - 编辑配置
heki uninstall      - 卸载
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

## 支持的面板

- SSPanel-UIM
- V2Board
- XBoard

## 配置示例

参考 [heki.conf.example](heki.conf.example)

## 文档

详细文档请访问：[heki-docs](https://hekicore.github.io/heki-docs/)

## Docker 镜像

```
docker pull hekicore/heki:latest
```

支持 `linux/amd64` 和 `linux/arm64` 双架构。
