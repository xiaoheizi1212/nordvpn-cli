# NordVPN Helper CLI (Windows)

A small **PowerShell helper CLI** that lets scripts (or an AI agent) drive the
**official NordVPN Windows app** — connect, change location, disconnect,
reconnect, check status — using the app's *own* documented command-line flags.

一个轻量的 **PowerShell 命令行助手**，让脚本（或 AI）调用**官方 NordVPN Windows 客户端**
来连接 / 换地区 / 断开 / 重连 / 查状态——用的是客户端**自带**的命令行参数。

---

## ⚠️ Disclaimer / 免责声明

- **For learning purposes only.** This is an unofficial, third-party *helper*.
  It is **not affiliated with, endorsed by, or connected to** NordVPN / Nord
  Security. "NordVPN" is a trademark of its respective owner.
- It does **not** modify, patch, crack, or bypass the NordVPN app, its
  licensing, or any security control. It only launches the official app with its
  **public, documented CLI flags** (the same ones Start-menu / jump-list
  shortcuts use) and reads your own network state.
- The author takes **NO responsibility** for any misuse, abuse, or damage.
  **Use at your own risk.**

- **仅供学习用途。** 这是一个非官方的第三方**助手工具**，与 NordVPN / Nord Security
  **无任何隶属、背书或关联**。「NordVPN」为其各自所有者的商标。
- 它**不**修改、破解、绕过 NordVPN 客户端、授权或任何安全机制；只是用官方客户端**公开、
  有文档的命令行参数**去触发（和开始菜单/跳转列表快捷方式一样），并读取你自己的网络状态。
- 作者对任何误用、滥用或损失**不承担任何责任**。**使用风险自负。**

---

## What it does / 功能

A config-driven launcher (`nv.ps1`) plus a low-level dispatcher (`nvpn.ps1`) and a
PowerShell module (`NordVpnCli.psm1`):

- **connect / change location / disconnect / reconnect** by country, server, or id
- **status** — protocol + active tunnel, and an optional *real exit* check
- **config.json** — your saved locations, favorites, defaults
- **schedule** — auto-reconnect on a countdown, or stay connected during a time range
- **catalog** — browse all NordVPN countries / cities (from Nord's public API)

配置驱动的启动器 `nv.ps1` + 底层调度器 `nvpn.ps1` + PowerShell 模块 `NordVpnCli.psm1`：
连接/换地区/断开/重连、状态、`config.json`（预设/收藏/默认）、定时调度、完整国家城市清单。

Designed to be **called by scripts or AI agents** — every action is a single,
predictable command line.

设计上就是给**脚本 / AI 调用**的——每个动作都是一条可预测的命令行。

---

## Prerequisites / 环境要求

| Requirement | Notes |
|---|---|
| **Windows 10 / 11** | uses PowerShell + the Windows NordVPN app |
| **Official NordVPN app**, installed & logged in | download from nordvpn.com; the helper drives this app, it does **not** log in for you |
| **Windows PowerShell 5.1+** | built into Windows (PowerShell 7 also works) |
| Microsoft Edge *(optional)* | only for `status -Verify` / `nv.ps1 where` real-exit check |
| .NET SDK *(optional)* | only if you want to re-run the `spike/Inspect` analysis tool |

- **Windows 10 / 11**；**官方 NordVPN 客户端**（已安装并登录——本工具只是调用它，**不会**替你登录）；
  **Windows PowerShell 5.1+**（系统自带）；Edge（可选，仅 `-Verify` 出口检测用）；.NET SDK（可选，仅重跑分析工具用）。

> The helper assumes the NordVPN app is **already installed and signed in**. It
> never handles your NordVPN account, password, or token.
> 本工具默认 NordVPN 客户端**已安装并登录**；它从不接触你的账号、密码或 token。

---

## Setup / 安装

```powershell
# 1. clone, then cd into the folder
git clone https://github.com/<you>/nordvpn-helper-cli.git
cd nordvpn-helper-cli

# 2. allow local scripts for THIS window only
Set-ExecutionPolicy -Scope Process Bypass -Force

# 3. create your config from the example (or just run nv.ps1 — it makes a default)
Copy-Item config.example.json config.json

# 4. try it
.\nv.ps1 status
.\nv.ps1 connect Japan
```

> If `NordVPN.exe` isn't at `C:\Program Files\NordVPN\NordVPN.exe`, edit
> `$script:NordVpnRoot` at the top of `NordVpnCli.psm1`.
> 若客户端不在默认路径，改 `NordVpnCli.psm1` 顶部的 `$script:NordVpnRoot`。

---

## Usage / 用法

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

**Full command reference: [COMMANDS.md](COMMANDS.md)**
完整命令参考见 [COMMANDS.md](COMMANDS.md)。

---

## How it works / 原理

- **Triggers** = the NordVPN app's own flags:
  `NordVPN.exe --connect [--group-name|--server-name|--server-id] | --disconnect`.
  These are fire-and-forget (the exe is a GUI app, so no console output); the
  tool confirms the result by observing your network state.
- **Status** = the Nord tunnel adapter that owns the default route, plus an
  optional *through-the-tunnel* exit check using headless Microsoft Edge
  (reliable even with split tunneling and UDP protocols like NordLynx).

- **触发** = 客户端自带 flags：`NordVPN.exe --connect [...] | --disconnect`（fire-and-forget，
  无控制台输出，工具靠观察网络状态确认）。**状态** = 走默认路由的 Nord 隧道 + 可选的「穿隧道 msedge 出口检测」。

What was deliberately **not** done: the app's encrypted gRPC control plane was
left untouched (no reverse-engineering of its auth layer).
刻意**没碰**的部分：客户端那条加密 gRPC 控制通道——没有逆向它的认证层。
The exact native CLI flags / 客户端原生 CLI 参数: [CLI-REFERENCE.md](CLI-REFERENCE.md)。

---

## Limitations / 限制

- **No protocol or city flag** in NordVPN's CLI. `--connect` uses the protocol
  set in the app (Automatic → NordLynx); location granularity is country/group,
  a specific server name, or a server id. Set protocol/city in the app GUI.
- Triggers are **fire-and-forget** (no return value); the tool polls state.
- `-Verify` / `where` launch a brief headless Edge and assume Edge is allowed
  through your VPN (relevant if you use split tunneling).

- NordVPN 的 CLI **没有协议 / 城市参数**：`--connect` 用客户端设置里的协议；地点粒度 =
  国家/组、服务器名、服务器 id；协议/城市在 GUI 里设。触发是 fire-and-forget。

---

## Files / 文件

| File | Purpose |
|---|---|
| `nv.ps1` | config-driven launcher (main) / 配置驱动启动器（主） |
| `nvpn.ps1` | low-level command dispatcher / 底层命令调度器 |
| `NordVpnCli.psm1` | the module (triggers + status) / 模块（触发 + 状态） |
| `config.example.json` | copy to `config.json` and edit / 复制成 `config.json` 再改 |
| `locations.json` | full country/city catalog (`nv.ps1 refresh` to update) / 完整清单 |
| `COMMANDS.md` | full command reference / 完整命令参考 |
| `CLI-REFERENCE.md` | NordVPN's own native CLI flags / 客户端原生 flags |
| `spike/Inspect/` | C# load-only inspector used for the analysis / 分析用 C# 工具 |

---

## License / 许可

[MIT](LICENSE). Not affiliated with NordVPN / Nord Security.
[MIT](LICENSE) 许可。与 NordVPN / Nord Security 无关联。
