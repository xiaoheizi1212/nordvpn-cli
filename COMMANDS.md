# 我们这个 NordVPN CLI — 全部功能

本工具自己的命令参考(`nv.ps1` 配置驱动启动器 + `nvpn.ps1` 底层调度器 + `NordVpnCli.psm1` 模块)。
触发用的是 NordVPN 自带的 `--connect/--disconnect` flags(那部分见 [CLI-REFERENCE.md](CLI-REFERENCE.md))。

运行前(每个新窗口一次)：
```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
```

---

## `nv.ps1` — 主力(配置驱动)

### 连接 / 切换

| 命令 | 作用 |
|---|---|
| `nv.ps1` | 不带参数 = 看状态 |
| `nv.ps1 <名字>` | 连接。名字解析顺序：你的 config 预设 → 完整 catalog 国家 → 当作原始国家名 |
| `nv.ps1 go [名字]` | 连到该名字；省略则连 `defaultLocation` |
| `nv.ps1 next` | 连到 `favorites` 里的下一个(循环) |
| `nv.ps1 reconnect [名字]` | 先断开再重连(到名字,或最优) |
| `nv.ps1 off` | 断开(别名：`disconnect`、`down`) |

### 状态 / 信息

| 命令 | 作用 |
|---|---|
| `nv.ps1 status` | 协议 + 隧道 + 服务器(加 `-Verify` 还会查真实出口)。别名 `st` |
| `nv.ps1 where` | 真实出口国家(穿过隧道用 msedge 测,UDP/分流都准) |

### 浏览地点

| 命令 | 作用 |
|---|---|
| `nv.ps1 list` | 你保存的预设(config.json)。别名 `ls` |
| `nv.ps1 all [过滤词]` | 全部 149 个 Nord 国家(locations.json)。别名 `countries` |
| `nv.ps1 cities <国家>` | 某国家的城市清单 |
| `nv.ps1 refresh` | 重新从 Nord API 下载完整国家/城市清单 |

### 预设管理(config.json 的 `locations`)

| 命令 | 作用 |
|---|---|
| `nv.ps1 add <名字> <国家>` | 保存一个预设(按国家/组) |
| `nv.ps1 add <名字> <值> -AsServer` | 保存为指定服务器名(如 `"Japan #45"`) |
| `nv.ps1 add <名字> <值> -AsId` | 保存为服务器 id |
| `nv.ps1 remove <名字>` | 删除一个预设。别名 `rm` |

### 收藏管理(config.json 的 `favorites`，全部写回文件)

| 命令 | 作用 |
|---|---|
| `nv.ps1 fav` | 列出收藏。别名 `favorites` |
| `nv.ps1 fav add <名字>` | 存一个收藏 |
| `nv.ps1 fav remove <名字>` | 删一个(别名 `rm`) |
| `nv.ps1 fav set <a> <b> ...` | 一次替换整个收藏列表 |
| `nv.ps1 fav clear` | 清空收藏 |

### 定时调度(config.json 的 `schedule`)

| 命令 | 作用 |
|---|---|
| `nv.ps1 schedule` | 显示调度设置(别名 `sched`) |
| `nv.ps1 schedule on` / `off` | 开 / 关开关(写回 config) |
| `nv.ps1 schedule run` | 前台运行调度循环(Ctrl+C 停) |
| `nv.ps1 schedule run -DryRun -MaxRuns 3` | 预览,不真的连 |

两种模式(config 里 `mode`):
- **countdown**:每隔 `countdownSec` 秒重连一次。`reconnectMode`:`favorite` = 按 `favorites` 轮流换国家;`fastest` = 每次重连最优(`--disconnect` 再 `--connect`)。
- **timeRange**:在 `timeRangeStart`–`timeRangeEnd` 之间保持连接(连到 `defaultLocation`),范围外自动断开。支持跨夜(start > end)。

> `run` 是**前台阻塞循环**——关窗口或 Ctrl+C 即停。想开机/后台自动跑,丢进 Windows 计划任务执行 `powershell -ExecutionPolicy Bypass -File "...\nv.ps1" schedule run`。
> countdown 间隔太短(<60s)会频繁打 Nord 服务器,脚本最低 15s 并会提示。`run` 默认要求 `enabled=true`(或用 `-Force` / `-DryRun`)。

### 帮助

`nv.ps1 help`(别名 `-h`、`--help`)

### 通用选项(可加在命令后)

| 选项 | 作用 |
|---|---|
| `-Verify` | 用 msedge 确认真实出口(status / connect / reconnect) |
| `-DryRun` | 只打印将要执行的 `NordVPN.exe ...` 命令,不真的连(用于 `go`/`<名字>`) |
| `-Via Cli\|AppExe` | 用哪个 exe(默认 `Cli` = `NordVPN.exe`) |
| `-TimeoutSec <n>` | 等待连接/断开的秒数 |
| `-AsServer` / `-AsId` | 配合 `add`,按服务器名 / id 保存 |

---

## `config.json` 结构

```json
{
  "defaultLocation": "singapore",
  "settings": { "via": "Cli", "timeoutSec": 30, "verifyByDefault": false },
  "favorites": [ "singapore", "japan" ],
  "locations": {
    "singapore": "Singapore",
    "work":     { "server": "Japan #45" },
    "fast":     { "id": "12345" }
  }
}
```

| 字段 | 说明 |
|---|---|
| `defaultLocation` | `nv.ps1 go` 不带名字时连这个 |
| `settings.via` | `Cli`(NordVPN.exe)或 `AppExe`(版本目录里的 NordVPNApp.exe) |
| `settings.timeoutSec` | 默认等待秒数 |
| `settings.verifyByDefault` | `true` 则每次都做 msedge 出口确认 |
| `favorites` | 有序列表,`nv.ps1 next` 按它循环 |
| `locations` | 你的预设。值可以是 **字符串**(国家/组)、`{ "server": "..." }`、或 `{ "id": "..." }` |
| `schedule` | 定时调度:`enabled` 开关、`mode`(`countdown`/`timeRange`)、`reconnectMode`(`favorite`/`fastest`,仅 countdown)、`countdownSec`、`timeRangeStart`、`timeRangeEnd` |

> 用 `add` / `remove` / `fav` 命令改 config 时,文件会被 PowerShell 按它的格式重排(仍是合法 JSON)。

---

## `nvpn.ps1` — 底层调度器(显式命令,不读 config)

| 命令 | 作用 |
|---|---|
| `nvpn.ps1 status [-Verify]` | 状态 |
| `nvpn.ps1 where` | 真实出口国家 |
| `nvpn.ps1 connect [国家]` | 连接(最优 / 国家)。`-Server "<名>"` 或 `-Id <id>` 指定服务器 |
| `nvpn.ps1 disconnect` | 断开 |
| `nvpn.ps1 reconnect [国家]` | 断开再重连 |
| `nvpn.ps1 countries [过滤词]` | 列出国家(直接查 Nord API) |
| `nvpn.ps1 help` | 帮助 |

选项：`-Verify`、`-Via Cli\|AppExe`、`-TimeoutSec <n>`、`-Server`、`-Id`

---

## 模块函数(给你写 PowerShell 脚本用)

```powershell
Import-Module .\NordVpnCli.psm1 -Force -DisableNameChecking
```

| 函数 | 用途 |
|---|---|
| `Connect-Nord [-Country\|-ServerName\|-ServerId] [-Verify] [-NoWait] [-Via] [-TimeoutSec]` | 连接 |
| `Disconnect-Nord [-Via] [-NoWait] [-TimeoutSec]` | 断开 |
| `Reconnect-Nord [-Country\|-ServerName\|-ServerId] [-Verify] [-Via] [-TimeoutSec]` | 重连 |
| `Get-NordStatus [-Verify] [-Quiet]` | 状态对象(VpnActive/Protocol/Server.../Exit...) |
| `Get-NordExitViaEdge` | 穿隧道的真实出口(msedge) |
| `Get-NordActiveTunnel` | 当前走默认路由的 Nord 适配器(=协议/连接) |
| `Get-NordServerEndpoint` / `Get-NordServerIpSet` | TCP 协议下的服务器端点 |
| `Get-NordCountries [-Match]` | Nord 国家列表(API) |
| `Wait-NordState -For Connected\|Disconnected [-TimeoutSec]` | 等待状态 |
| `Invoke-NordCli -Arguments @('--connect','--group-name','Japan') [-Via] [-PassThruCommand]` | 直接发底层 flag |
| `Get-NordVpnExe` / `Get-NordVpnAppExe` / `ConvertTo-NordArgLine` | 辅助 |

---

## 原理(一句话)

- **触发** = `NordVPN.exe --connect [--group-name|--server-name|--server-id] | --disconnect`(fire-and-forget,无 stdout,工具靠观察状态确认)。
- **状态** = 默认路由的 Nord 隧道 + 可选的「穿隧道 msedge 出口检查」(`-Verify` / `where`)。因为你开了 **app 分流(只有 msedge 走 VPN)** 且 NordLynx 是 UDP,所以普通 IP 检查不准,只有 Edge 出口检查是真的。

---

## 常见用法

```powershell
# 日常
.\nv.ps1 go                 # 连默认
.\nv.ps1 off                # 断开
.\nv.ps1 status -Verify     # 看真实出口

# 换国家
.\nv.ps1 Japan              # 不在预设也能连
.\nv.ps1 add jp Japan       # 存成预设
.\nv.ps1 jp                 # 以后直接用

# 收藏 + 循环
.\nv.ps1 fav set singapore japan us
.\nv.ps1 next               # 轮到下一个

# 指定服务器
.\nvpn.ps1 connect -Server "Japan #45"
```

---

## 限制

- NordVPN 的 CLI **没有协议(protocol)和城市(city)参数** —— `connect` 用 app 设置里的协议(Automatic→NordLynx);地点粒度 = 国家/组、服务器名、服务器 id。城市级要用该城市的某台服务器名/id。协议/城市在 GUI 里设。
- `cities` 只是**参考清单**(CLI 不支持按城市连)。
- `-Verify` / `where` 会起一个短暂的 headless msedge,依赖 msedge 在你的分流名单里。
- 完整 catalog 在 `locations.json`(`nv.ps1 refresh` 更新);`config.json` 是你自己的精选。
