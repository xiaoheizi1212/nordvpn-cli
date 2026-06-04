<#
  Test-NordVpnCli.ps1  -  self test / 自检脚本

  DRY-RUN by default: shows the exact NordVPN.exe commands each action runs and
  reads current status, without changing your connection.
  默认 DRY-RUN(干跑):只打印每个动作实际执行的 NordVPN.exe 命令并读取当前状态,
  不会改动你的连接。

  Live mode (changes your connection - reversible) / 实连模式(会改动连接,可逆):
     .\Test-NordVpnCli.ps1 -Live -Country Japan
  Captures before-state, connects to the country, verifies the real exit via
  msedge, prints the verdict. Add -ThenReconnectBest to finish on best server.
  记录连接前状态 -> 连到该国家 -> 用 msedge 验证真实出口 -> 给出结论。
  加 -ThenReconnectBest 则最后回到最优服务器。
#>
[CmdletBinding()]
param(
    [switch]$Live,
    [string]$Country = 'Japan',
    [ValidateSet('Cli','AppExe')][string]$Via = 'Cli',
    [switch]$ThenReconnectBest,
    [int]$TimeoutSec = 30
)
Import-Module (Join-Path $PSScriptRoot 'NordVpnCli.psm1') -Force -DisableNameChecking
$bar = ('-' * 64)
Write-Host $bar; Write-Host " NordVPN CLI wrapper - self test" -ForegroundColor Cyan; Write-Host $bar

Write-Host "`n[1] Environment" -ForegroundColor Cyan
try { Write-Host "    launcher : $(Get-NordVpnExe)" } catch { Write-Host "    launcher : NOT FOUND" -ForegroundColor Red }
Write-Host "    app exe  : $(Get-NordVpnAppExe)"

Write-Host "`n[2] Exact commands these actions run (NOT executed)" -ForegroundColor Cyan
@(
    @('--connect'),
    @('--connect','--group-name',$Country),
    @('--connect','--server-name','United States #5'),
    @('--disconnect')
) | ForEach-Object { Write-Host ("    {0,-34} ->  {1}" -f ($_ -join ' '), (Invoke-NordCli -Arguments $_ -Via $Via -PassThruCommand)) }

Write-Host "`n[3] Current status (read-only)" -ForegroundColor Cyan
$before = Get-NordStatus

if (-not $Live) {
    Write-Host "`n[4] Live test SKIPPED (dry-run)." -ForegroundColor DarkGray
    Write-Host "    Real connect test:  .\Test-NordVpnCli.ps1 -Live -Country `"$Country`"" -ForegroundColor DarkGray
    Write-Host "`nDone (no connection changes)." -ForegroundColor Green
    return
}

Write-Host "`n[4] LIVE TEST - will connect to '$Country' (changes your connection)" -ForegroundColor Yellow
if ((Read-Host "    type 'yes' to proceed") -ne 'yes') { Write-Host "    aborted." -ForegroundColor DarkGray; return }

$res = Connect-Nord -Country $Country -Via $Via -Verify -TimeoutSec $TimeoutSec

Write-Host "`n[5] Verdict" -ForegroundColor Cyan
if ($res.VpnActive -and $res.ExitCountry) {
    Write-Host ("    PASS - connected ({0}); real exit = {1} ({2})." -f $res.Protocol, $res.ExitCountry, $res.ExitCity) -ForegroundColor Green
} elseif ($res.VpnActive) {
    Write-Host ("    PARTIAL - tunnel up ({0}) but could not verify exit via msedge." -f $res.Protocol) -ForegroundColor Yellow
} else {
    Write-Host "    FAIL - tunnel not active after connect." -ForegroundColor Red
}

if ($ThenReconnectBest) { Write-Host "`n[6] Reconnecting to best ..." -ForegroundColor Cyan; Connect-Nord -Via $Via | Out-Null }
else { Write-Host "`n[6] Left connected to '$Country'. Restore with: .\nvpn.ps1 reconnect" -ForegroundColor DarkGray }
