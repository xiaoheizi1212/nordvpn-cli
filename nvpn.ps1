<#
  nvpn.ps1  -  low-level CLI for NordVPN via the app's own launch flags (verified on 8.4.3.0).
  底层 CLI:用客户端自带的命令行参数驱动 NordVPN(8.4.3.0 实测)。
  (For the config-driven launcher use nv.ps1. / 配置驱动的启动器请用 nv.ps1。)

    .\nvpn.ps1 status [-Verify]        # status; -Verify also checks real exit via msedge / 状态;-Verify 还会查真实出口
    .\nvpn.ps1 where                   # definitive exit country (through the tunnel/msedge) / 真实出口国家
    .\nvpn.ps1 connect                 # quick connect (best) / 快速连接(最优)
    .\nvpn.ps1 connect Japan           # connect to a country / group / 连到某国家或组
    .\nvpn.ps1 connect -Server "United States #5"   # by server name / 按服务器名
    .\nvpn.ps1 connect -Id 12345                    # by server id   / 按服务器 id
    .\nvpn.ps1 disconnect              # disconnect / 断开
    .\nvpn.ps1 reconnect [location]    # disconnect then reconnect (best or location) / 断开再重连
    .\nvpn.ps1 countries [filter]      # list valid country names / ids / 列出国家名与 id

  Options / 选项: -Server <name>  -Id <id>  -Verify  -Via Cli|AppExe  -TimeoutSec <n>
  Underlying calls / 底层实际调用:  NordVPN.exe --connect [--group-name|--server-name|--server-id] | --disconnect
#>
[CmdletBinding()]
param(
    [Parameter(Position=0)][string]$Command = 'status',
    [Parameter(Position=1)][string]$Location,
    [string]$Server,
    [string]$Id,
    [switch]$Verify,
    [ValidateSet('Cli','AppExe')][string]$Via = 'Cli',
    [int]$TimeoutSec = 30
)
Import-Module (Join-Path $PSScriptRoot 'NordVpnCli.psm1') -Force -DisableNameChecking

function Show-Help {
@"
NordVPN CLI (uses the app's own --flags; verified on 8.4.3.0)

  nvpn status [-Verify]            connection status (+ real exit if -Verify)
  nvpn where                      definitive exit country (through the tunnel)
  nvpn connect [location]         quick connect, or to a country/group
  nvpn connect -Server "<name>"   connect to a specific server
  nvpn connect -Id <id>           connect to a server id
  nvpn disconnect                 disconnect
  nvpn reconnect [location]       disconnect then reconnect
  nvpn countries [filter]         list country names / ids
  nvpn help                       this help
"@ | Write-Host
}

switch ($Command.ToLower()) {
    'status'     { Get-NordStatus -Verify:$Verify | Out-Null }
    'where'      { $e = Get-NordExitViaEdge; if ($e) { Write-Host ("exit: {0}  {1}{2}  [{3}]" -f $e.Ip,$e.Country,$(if($e.City){", $($e.City)"}),$e.Org) -ForegroundColor Green } else { Write-Host "could not determine exit via msedge" -ForegroundColor Yellow } }
    'countries'  { Get-NordCountries -Match $Location | Format-Table -Auto }

    'connect' {
        if     ($Server)   { Connect-Nord -ServerName $Server -Via $Via -Verify:$Verify -TimeoutSec $TimeoutSec }
        elseif ($Id)       { Connect-Nord -ServerId $Id       -Via $Via -Verify:$Verify -TimeoutSec $TimeoutSec }
        elseif ($Location) { Connect-Nord -Country $Location  -Via $Via -Verify:$Verify -TimeoutSec $TimeoutSec }
        else               { Connect-Nord                     -Via $Via -Verify:$Verify -TimeoutSec $TimeoutSec }
    }
    'disconnect' { Disconnect-Nord -Via $Via }
    'reconnect' {
        if     ($Server)   { Reconnect-Nord -ServerName $Server -Via $Via -Verify:$Verify -TimeoutSec $TimeoutSec }
        elseif ($Id)       { Reconnect-Nord -ServerId $Id       -Via $Via -Verify:$Verify -TimeoutSec $TimeoutSec }
        elseif ($Location) { Reconnect-Nord -Country $Location  -Via $Via -Verify:$Verify -TimeoutSec $TimeoutSec }
        else               { Reconnect-Nord                     -Via $Via -Verify:$Verify -TimeoutSec $TimeoutSec }
    }

    'help'       { Show-Help }
    default      { Write-Host "Unknown command '$Command'." -ForegroundColor Red; Show-Help }
}
