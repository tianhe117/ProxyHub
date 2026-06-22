# ProxyHub

自托管的代理服务管理面板，提供 Web UI 统一管理多个代理引擎的入站、出站、订阅和节点，支持节点健康检测。

## 平台支持

仅支持 **Ubuntu 22.04+ (amd64)**。

## 核心功能

- **订阅管理** — 解析 `vmess://`、`ss://` 链接和 Clash YAML 格式，支持关键字过滤
- **节点管理** — 批量 TCP/HTTP 延迟检测，自定义节点，按订阅分组
- **入站管理** — 定义本地监听（HTTP/SOCKS5/Shadowsocks/VMess）
- **出站管理** — 定义出口策略（单节点 / 自动故障转移节点池）
- **服务管理** — 组合入站+出站，启动实际的代理进程
- **二进制升级** — 从 GitHub Releases 下载最新代理引擎
- **实时日志** — Web 端日志面板
- **会话认证** — 用户名/密码登录

## 支持的代理引擎

| 引擎 | 用途 |
|------|------|
| [Xray](https://github.com/XTLS/Xray-core) | VMess/VLESS/Trojan/Shadowsocks/HTTP/SOCKS |
| [shadowsocks-rust](https://github.com/shadowsocks/shadowsocks-rust) | Shadowsocks + obfs 插件 |
| [sing-box](https://github.com/SagerNet/sing-box) | Hysteria2 / TUIC |

## 快速部署

```bash
chmod +x setup.sh
./setup.sh
./venv/bin/python run.py
```

浏览器打开 `http://<server-ip>:8080`。

## 项目结构

参阅 [docs/DESIGN.md](docs/DESIGN.md)。

## License

MIT
