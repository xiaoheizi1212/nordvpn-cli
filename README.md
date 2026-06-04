# NordVPN Helper CLI (Windows)

A PowerShell **helper CLI** that lets scripts (or an AI agent) drive the **official
NordVPN Windows app** — connect, change location, disconnect, reconnect, check
status — using the app's *own* documented command-line flags.

**Language / 语言: [English](#english) · [中文](#中文)**

---

<a id="english"></a>
# English

## ⚠️ Disclaimer

- **For learning purposes only.** This is an unofficial, third-party *helper*. It
  is **not affiliated with, endorsed by, or connected to** NordVPN / Nord Security.
  "NordVPN" is a trademark of its respective owner.
- It does **not** modify, patch, crack, or bypass the NordVPN app, its licensing,
  or any security control. It only launches the official app with its **public,
  documented CLI flags** (the same ones Start-menu / jump-list shortcuts use) and
  reads your own network state.
- The author takes **NO responsibility** for any misuse, abuse, or damage.
  **Use at your own risk.**

## What it does

A config-driven launcher (`nv.ps1`) plus a low-level dispatcher (`nvpn.ps1`) and a
PowerShell module (`NordVpnCli.psm1`):

- **connect / change location / disconnect / reconnect** by country, server, or id
- **status** — protocol + active tunnel, with an optional *real exit* check
- **config.json** — your saved locations, favorites, defaults
- **schedule** — auto-reconnect on a countdown, or stay connected during a time range
- **catalog** — browse all NordVPN countries / cities (from Nord's public API)

It is designed to be **called by scripts or AI agents** — every action is a single,
predictable command line.

## Prerequisites

| Requirement | Notes |
|---|---|
| **Windows 10 / 11** | uses PowerShell + the Windows NordVPN app |
| **Official NordVPN app**, installed & logged in | download from nordvpn.com; the helper drives this app, it does **not** log in for you |
| **Windows PowerShell 5.1+** | built into Windows (PowerShell 7 also works) |
| Microsoft Edge *(optional)* | only for `status -Verify` / `nv.ps1 where` real-exit check |
| .NET SDK *(optional)* | only if you want to re-run the `spike/Inspect` analysis tool |

The helper assumes the NordVPN app is **already installed and signed in**. It never
handles your NordVPN account, password, or token.

## Setup

```powershell
git clone https://github.com/xiaoheizi1212/nordvpn-cli.git
cd nordvpn-cli

# allow local scripts for THIS window only
Set-ExecutionPolicy -Scope Process Bypass -Force

# create your config from the example (or just run nv.ps1 — it makes a default)
Copy-Item config.example.json config.json

.\nv.ps1 status
.\nv.ps1 connect Japan
```

If `NordVPN.exe` isn't at `C:\Program Files\NordVPN\NordVPN.exe`, edit
`$script:NordVpnRoot` at the top of `NordVpnCli.psm1`.

## Usage

```powershell
.\nv.ps1                       # status (default)
.\nv.ps1 japan                 # connect: your preset -> catalog country -> raw country
.\nv.ps1 go                    # connect to defaultLocation
.\nv.ps1 reconnect             # disconnect then reconnect
.\nv.ps1 off                   # disconnect
.\nv.ps1 status -Verify        # state + real exit country (through the tunnel)
.\nv.ps1 all united            # browse all Nord countries (filter)
.\nv.ps1 fav add japan         # save a favorite to config.json
.\nv.ps1 schedule run -DryRun  # preview the auto-reconnect scheduler
.\nv.ps1 help                  # full command list
```

Full command reference: [COMMANDS.md](COMMANDS.md).

## How it works

- **Triggers** = the NordVPN app's own flags:
  `NordVPN.exe --connect [--group-name|--server-name|--server-id] | --disconnect`.
  These are fire-and-forget (the exe is a GUI app, so no console output); the tool
  confirms the result by observing your network state.
- **Status** = the Nord tunnel adapter that owns the default route, plus an optional
  *through-the-tunnel* exit check using headless Microsoft Edge (reliable even with
  split tunneling and UDP protocols like NordLynx).

What was deliberately **not** done: the app's encrypted gRPC control plane was left
untouched (no reverse-engineering of its auth layer). The exact native CLI flags
are in [CLI-REFERENCE.md](CLI-REFERENCE.md).

## Limitations

- **No protocol or city flag** in NordVPN's CLI. `--connect` uses the protocol set
  in the app (Automatic → NordLynx); location granularity is country/group, a
  specific server name, or a server id. Set protocol/city in the app GUI.
- Triggers are **fire-and-forget** (no return value); the tool polls state.
- `-Verify` / `where` launch a brief headless Edge and assume Edge is allowed
  through your VPN (relevant if you use split tunneling).

## Files

| File | Purpose |
|---|---|
| `nv.ps1` | config-driven launcher (main) |
| `nvpn.ps1` | low-level command dispatcher |
| `NordVpnCli.psm1` | the module (triggers + status) |
| `config.example.json` | copy to `config.json` and edit |
| `locations.json` | full country/city catalog (`nv.ps1 refresh` to update) |
| `COMMANDS.md` | full command reference |
| `CLI-REFERENCE.md` | NordVPN's own native CLI flags |
| `spike/Inspect/` | C# load-only inspector used for the analysis |

## Credits

- **Reverse-engineered & built by Claude** (Anthropic's AI).
- **Idea by [xiaoheizi1212](https://github.com/xiaoheizi1212).**

## License

[MIT](LICENSE). Not affiliated with NordVPN / Nord Security.

---

<a id="中文"></a>
# 中文

## ⚠️ 免责声明

- **仅供学习用途。** 这是一个非官方的第三方**助手工具**,与 NordVPN / Nord Security
  **无任何隶属、背书或关联**。「NordVPN」为其各自所有者的商标。
- 它**不**修改、破解、绕过 NordVPN 客户端、授权或任何安全机制;只是用官方客户端**公开、
  有文档的命令行参数**去触发(和开始菜单/跳转列表快捷方式一样),并读取你自己的网络状态。
- 作者对任何误用、滥用或损失**不承担任何责任**。**使用风险自负。**

## 功能

配置驱动的启动器 `nv.ps1` + 底层调度器 `nvpn.ps1` + PowerShell 模块 `NordVpnCli.psm1`:

- **连接 / 换地区 / 断开 / 重连** —— 按国家、服务器名或服务器 id
- **状态** —— 协议 + 当前隧道,可选「真实出口」检测
- **config.json** —— 你保存的地点、收藏、默认值
- **定时调度** —— 倒计时自动重连,或在某时间段内保持连接
- **完整清单** —— 浏览所有 NordVPN 国家/城市(来自 Nord 公开 API)

设计上就是给**脚本 / AI 调用**的 —— 每个动作都是一条可预测的命令行。

## 环境要求

| 要求 | 说明 |
|---|---|
| **Windows 10 / 11** | 使用 PowerShell + Windows 版 NordVPN 客户端 |
| **官方 NordVPN 客户端**(已安装并登录) | 从 nordvpn.com 下载;本工具只是调用它,**不会**替你登录 |
| **Windows PowerShell 5.1+** | 系统自带(PowerShell 7 也可) |
| Microsoft Edge(可选) | 仅 `status -Verify` / `nv.ps1 where` 出口检测用 |
| .NET SDK(可选) | 仅当你想重跑 `spike/Inspect` 分析工具 |

本工具默认 NordVPN 客户端**已安装并登录**;它从不接触你的账号、密码或 token。

## 安装

```powershell
git clone https://github.com/xiaoheizi1212/nordvpn-cli.git
cd nordvpn-cli

# 仅对当前窗口允许运行本地脚本
Set-ExecutionPolicy -Scope Process Bypass -Force

# 从示例创建你的配置(或直接运行 nv.ps1,它会生成默认配置)
Copy-Item config.example.json config.json

.\nv.ps1 status
.\nv.ps1 connect Japan
```

若客户端不在 `C:\Program Files\NordVPN\NordVPN.exe`,改 `NordVpnCli.psm1` 顶部的
`$script:NordVpnRoot`。

## 用法

```powershell
.\nv.ps1                       # 状态(默认)
.\nv.ps1 japan                 # 连接:先查预设 -> catalog 国家 -> 原始国家名
.\nv.ps1 go                    # 连到 defaultLocation
.\nv.ps1 reconnect             # 断开再重连
.\nv.ps1 off                   # 断开
.\nv.ps1 status -Verify        # 状态 + 真实出口国家(穿过隧道)
.\nv.ps1 all united            # 浏览所有 Nord 国家(可过滤)
.\nv.ps1 fav add japan         # 保存一个收藏到 config.json
.\nv.ps1 schedule run -DryRun  # 预览自动重连调度
.\nv.ps1 help                  # 完整命令列表
```

完整命令参考见 [COMMANDS.md](COMMANDS.md)。

## 原理

- **触发** = 客户端自带参数:
  `NordVPN.exe --connect [--group-name|--server-name|--server-id] | --disconnect`。
  这些是 fire-and-forget(GUI 程序,无控制台输出),工具靠观察网络状态确认结果。
- **状态** = 走默认路由的 Nord 隧道适配器,加可选的「穿隧道 msedge 出口检测」(即使开了
  分流、或用 NordLynx/UDP 也准确)。

**刻意没碰**的部分:客户端那条加密 gRPC 控制通道——没有逆向它的认证层。客户端原生 CLI
参数见 [CLI-REFERENCE.md](CLI-REFERENCE.md)。

## 限制

- NordVPN 的 CLI **没有协议 / 城市参数**。`--connect` 用客户端设置里的协议
  (Automatic → NordLynx);地点粒度 = 国家/组、服务器名、服务器 id;协议/城市在 GUI 里设。
- 触发是 **fire-and-forget**(无返回值),工具轮询状态确认。
- `-Verify` / `where` 会起一个短暂的无头 Edge,前提是 Edge 在你的分流名单内。

## 文件

| 文件 | 用途 |
|---|---|
| `nv.ps1` | 配置驱动启动器(主) |
| `nvpn.ps1` | 底层命令调度器 |
| `NordVpnCli.psm1` | 模块(触发 + 状态) |
| `config.example.json` | 复制成 `config.json` 再改 |
| `locations.json` | 完整国家/城市清单(`nv.ps1 refresh` 更新) |
| `COMMANDS.md` | 完整命令参考 |
| `CLI-REFERENCE.md` | 客户端原生 CLI 参数 |
| `spike/Inspect/` | 分析用的 C#「只加载不执行」检查工具 |

## 致谢

- **逆向分析与实现:Claude**(Anthropic 的 AI)。
- **创意 / 点子:[xiaoheizi1212](https://github.com/xiaoheizi1212)。**

## 许可

[MIT](LICENSE)。与 NordVPN / Nord Security 无关联。
