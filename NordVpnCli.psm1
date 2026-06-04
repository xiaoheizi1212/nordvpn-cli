# =====================================================================
#  NordVpnCli.psm1  -  Local automation wrapper for the NordVPN Windows app.
#  本地自动化封装，调用 NordVPN Windows 客户端。
#
#  TRIGGERS use NordVPN's own documented launch FLAGS (verified on 8.4.3.0),
#  the same ones Start-menu / jump-list shortcuts use:
#  触发使用 NordVPN 自带的命令行参数（8.4.3.0 实测有效），与开始菜单/跳转列表快捷方式相同：
#       NordVPN.exe --connect
#       NordVPN.exe --connect --group-name "Japan"
#       NordVPN.exe --connect --server-name "United States #5"
#       NordVPN.exe --connect --server-id 12345
#       NordVPN.exe --disconnect
#  NOTE: the syntax is --connect / --disconnect, NOT bare "connect".
#  注意：语法是 --connect / --disconnect，不是裸词 "connect"。
#  No reverse-engineering, no protocol circumvention -- just the app's CLI.
#  不逆向、不绕过任何机制——只用客户端自带的 CLI。
#
#  STATUS is read two ways / 状态有两种读法：
#   * fast  : active Nord tunnel (default-route adapter) + TCP server endpoint.
#             快速：走默认路由的 Nord 隧道 + nordvpn-service 的 TCP 服务器端点。
#   * exact : Get-NordExitViaEdge runs a headless msedge check THROUGH the tunnel.
#             精确：用无头 msedge 穿过隧道测出口（NordLynx/UDP 和分流下唯一可靠）。
#
#  Nothing here modifies the NordVPN installation.
#  本文件不修改 NordVPN 的任何安装文件。
# =====================================================================

# Install path of the NordVPN app. Change if yours differs.
# NordVPN 客户端安装路径，若不同请修改。
$script:NordVpnRoot = 'C:\Program Files\NordVPN'

# ---------------------------------------------------------------------
#  Launcher / 启动器定位
# ---------------------------------------------------------------------
# Stable top-level launcher (NordVPN.exe). / 稳定的顶层启动器 NordVPN.exe。
function Get-NordVpnExe {
    $c = Join-Path $script:NordVpnRoot 'NordVPN.exe'
    if (Test-Path $c) { return $c }
    throw "NordVPN.exe not found at '$c'."
}
# Latest versioned NordVPNApp.exe (fallback trigger). / 最新版本目录里的 NordVPNApp.exe（备用触发）。
function Get-NordVpnAppExe {
    Get-ChildItem $script:NordVpnRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+(\.\d+){3}$' } |
        Sort-Object { [version]$_.Name } -Descending |
        ForEach-Object { $e = Join-Path $_.FullName 'NordVPNApp.exe'; if (Test-Path $e) { return $e } } |
        Select-Object -First 1
}
# Quote an argv array into one Windows command-line tail. / 把参数数组拼成带引号的命令行。
function ConvertTo-NordArgLine {
    param([Parameter(Mandatory)][string[]]$Arguments)
    ($Arguments | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"','\"') + '"' } else { $_ } }) -join ' '
}
# Fire a CLI verb at the app (fire-and-forget). / 向客户端发一条命令（fire-and-forget）。
function Invoke-NordCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [ValidateSet('Cli','AppExe')][string]$Via = 'Cli',
        [switch]$PassThruCommand   # only print the command, don't run it / 只打印命令、不执行
    )
    $exe = if ($Via -eq 'AppExe') { Get-NordVpnAppExe } else { Get-NordVpnExe }
    if (-not $exe) { throw 'NordVPN executable not found.' }
    $line = ConvertTo-NordArgLine -Arguments $Arguments
    if ($PassThruCommand) { return ('"{0}" {1}' -f $exe, $line) }
    Start-Process -FilePath $exe -ArgumentList $line -WindowStyle Hidden | Out-Null
}

# ---------------------------------------------------------------------
#  Local signals / 本地信号（判断连接状态）
# ---------------------------------------------------------------------
# Friendly protocol name from adapter name/description. / 由适配器名/描述得出协议名。
function Get-NordProtocolName([string]$name,[string]$desc) {
    if ($name -match 'NordLynx'    -or $desc -match 'NordLynx')    { return 'NordLynx (WireGuard/UDP)' }
    if ($name -match 'NordWhisper' -or $desc -match 'NordWhisper') { return 'NordWhisper (TCP)' }
    if ($desc -match 'OpenVPN' -or $desc -match 'TAP')            { return 'OpenVPN' }
    return $desc
}
# The Nord tunnel that owns the default route == the live connection.
# 走默认路由的 Nord 隧道 == 当前真正在用的连接。
function Get-NordActiveTunnel {
    $defs = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric
    foreach ($r in $defs) {
        $ad = Get-NetAdapter -InterfaceIndex $r.ifIndex -ErrorAction SilentlyContinue
        if ($ad -and ($ad.Name -match 'NordLynx|NordWhisper' -or $ad.InterfaceDescription -match 'NordLynx|NordWhisper|Nord')) {
            $cfg = Get-NetIPConfiguration -InterfaceIndex $ad.ifIndex -ErrorAction SilentlyContinue
            return [pscustomobject]@{ Adapter=$ad.Name; Protocol=(Get-NordProtocolName $ad.Name $ad.InterfaceDescription); TunnelIP=($cfg.IPv4Address.IPAddress -join ','); Metric=$r.RouteMetric }
        }
    }
    return $null
}
# TCP server endpoint(s) of nordvpn-service (visible for TCP protocols only).
# nordvpn-service 的 TCP 服务器端点（只有 TCP 协议可见；NordLynx 是 UDP 看不到）。
function Get-NordServerIpSet {
    $svc = Get-Process -Name 'nordvpn-service' -ErrorAction SilentlyContinue
    if (-not $svc) { return @() }
    $ids = @($svc.Id)
    Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
        Where-Object { $ids -contains $_.OwningProcess -and $_.RemotePort -notin 8886,8883,80 -and
                       $_.RemoteAddress -notmatch '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|127\.|169\.254\.|::1|fe80|0\.0\.0\.0)' } |
        Select-Object -ExpandProperty RemoteAddress -Unique
}
# Geolocate the server endpoint, skipping cloud/CDN (= the app's API, not the VPN server).
# 给服务器端点做地理定位，跳过云/CDN（那是客户端的 API，不是 VPN 服务器）。
function Get-NordServerEndpoint {
    param([int]$TimeoutSec = 6)
    $cloud = 'Amazon|Cloudflare|Google|Microsoft|Akamai|Fastly|DigitalOcean'
    $best = $null
    foreach ($ip in @(Get-NordServerIpSet)) {
        try { $g = Invoke-RestMethod "http://ip-api.com/json/$ip" -TimeoutSec $TimeoutSec } catch { continue }
        $o = [pscustomobject]@{ Ip=$ip; Country=$g.country; City=$g.city; Isp=$g.isp }
        if ($g.isp -notmatch $cloud -and $g.org -notmatch $cloud) { return $o }
        # else: a cloud/CDN IP (e.g. api.nordvpn.com) -- NOT the VPN server; ignore it
        # 否则是云/CDN IP（如 api.nordvpn.com）——不是 VPN 服务器，忽略
    }
    return $null
}

# Definitive exit as seen by an in-tunnel app (msedge): correct for ALL protocols
# (incl. NordLynx/UDP) and under split tunneling.
# 用隧道内的应用（msedge）看到的真实出口：对所有协议（含 NordLynx/UDP）和分流都准确。
function Get-NordExitViaEdge {
    param([int]$TimeoutSec = 25)
    $edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    if (-not (Test-Path $edge)) { $edge = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe" }
    if (-not (Test-Path $edge)) { return $null }
    $udd = Join-Path $env:TEMP ('edgenv_' + (Get-Random))   # throwaway profile / 一次性配置目录
    $out = Join-Path $env:TEMP ('edgeip_' + (Get-Random) + '.txt')
    $err = Join-Path $env:TEMP ('edgeerr_' + (Get-Random) + '.txt')
    try {
        # headless Edge -> goes through the tunnel -> dump an IP-echo page / 无头 Edge 走隧道，抓 IP 回显页
        $a = @('--headless','--disable-gpu','--no-first-run','--no-default-browser-check','--log-level=3',"--user-data-dir=$udd",'--dump-dom','https://ipinfo.io/json')
        $p = Start-Process -FilePath $edge -ArgumentList $a -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -PassThru
        if (-not $p.WaitForExit($TimeoutSec * 1000)) { try { $p.Kill() } catch {} }
        $raw = Get-Content $out -Raw -ErrorAction SilentlyContinue
        $m = [regex]::Match([string]$raw, '\{[\s\S]*?\}')
        if ($m.Success) { $j = $m.Value | ConvertFrom-Json; return [pscustomobject]@{ Ip=$j.ip; Country=$j.country; City=$j.city; Org=$j.org } }
    } catch { } finally {
        Remove-Item $out, $err -ErrorAction SilentlyContinue
        Remove-Item $udd -Recurse -Force -ErrorAction SilentlyContinue
    }
    return $null
}

# Combined status. -Verify also does the (slower) Edge exit check.
# 综合状态。-Verify 会额外做（较慢的）Edge 出口检测。
function Get-NordStatus {
    [CmdletBinding()] param([switch]$Quiet, [switch]$Verify)
    $tunnel = Get-NordActiveTunnel
    $server = if ($tunnel) { Get-NordServerEndpoint } else { $null }
    $active = [bool]$tunnel
    $exit   = if ($Verify -and $active) { Get-NordExitViaEdge } else { $null }

    $s = [pscustomobject]@{
        VpnActive   = $active
        Protocol    = if ($tunnel) { $tunnel.Protocol } else { '(none)' }
        ServerIp    = if ($server) { $server.Ip } else { $null }
        ServerCountry = if ($server) { $server.Country } else { $null }
        ServerCity  = if ($server) { $server.City } else { $null }
        TunnelIp    = if ($tunnel) { $tunnel.TunnelIP } else { $null }
        Adapter     = if ($tunnel) { $tunnel.Adapter } else { $null }
        ExitCountry = if ($exit) { $exit.Country } else { $null }
        ExitCity    = if ($exit) { $exit.City } else { $null }
        ExitIp      = if ($exit) { $exit.Ip } else { $null }
    }
    if (-not $Quiet) {
        $mark = if ($active) { '[VPN ACTIVE]' } else { '[VPN OFF]' }
        $col  = if ($active) { 'Green' } else { 'Yellow' }
        Write-Host ''
        Write-Host " $mark" -ForegroundColor $col
        Write-Host ("   Protocol : {0}" -f $s.Protocol)
        if ($s.ServerIp)      { Write-Host ("   Server   : {0}  ({1}{2})" -f $s.ServerIp, $s.ServerCountry, $(if($s.ServerCity){", $($s.ServerCity)"})) -ForegroundColor $col }
        elseif ($active)      { Write-Host  "   Server   : (UDP protocol - not visible via netstat; use -Verify for exit)" }
        if ($s.TunnelIp)      { Write-Host ("   Tunnel   : {0} on {1}" -f $s.TunnelIp, $s.Adapter) }
        if ($s.ExitIp)        { Write-Host ("   Exit(edge): {0}  ({1}{2})" -f $s.ExitIp, $s.ExitCountry, $(if($s.ExitCity){", $($s.ExitCity)"})) -ForegroundColor Green }
        elseif ($Verify -and $active) { Write-Host "   Exit(edge): (could not determine via msedge)" -ForegroundColor Yellow }
        Write-Host ''
    }
    return $s
}

# Poll until connected / disconnected, or timeout. / 轮询直到已连/已断，或超时。
function Wait-NordState {
    param([ValidateSet('Connected','Disconnected')][string]$For, [int]$TimeoutSec = 30, [int]$PollSec = 2)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    do {
        Start-Sleep -Seconds $PollSec
        $t = Get-NordActiveTunnel
        if ($For -eq 'Connected'    -and $t)  { return $true }
        if ($For -eq 'Disconnected' -and -not $t) { return $true }
    } while ((Get-Date) -lt $deadline)
    return $false
}

# ---------------------------------------------------------------------
#  ACTIONS  (NordVPN's own --flags) / 动作（用 NordVPN 自带 --flags）
# ---------------------------------------------------------------------
# Connect: best, or by -Country / -ServerName / -ServerId. / 连接：最优，或按国家/服务器名/服务器id。
function Connect-Nord {
    [CmdletBinding(DefaultParameterSetName='Best')]
    param(
        [Parameter(ParameterSetName='Country', Position=0)][Alias('Group')][string]$Country,
        [Parameter(ParameterSetName='ServerName')][string]$ServerName,
        [Parameter(ParameterSetName='ServerId')][string]$ServerId,
        [ValidateSet('Cli','AppExe')][string]$Via = 'Cli',
        [switch]$NoWait, [switch]$Verify, [int]$TimeoutSec = 30
    )
    switch ($PSCmdlet.ParameterSetName) {
        'Country'    { $a = @('--connect','--group-name',$Country); $t = $Country }
        'ServerName' { $a = @('--connect','--server-name',$ServerName); $t = $ServerName }
        'ServerId'   { $a = @('--connect','--server-id',$ServerId); $t = "id:$ServerId" }
        default      { $a = @('--connect'); $t = 'best server' }
    }
    Write-Host ("-> --connect $($t) ...") -ForegroundColor Cyan
    Invoke-NordCli -Arguments $a -Via $Via
    if ($NoWait) { return }
    if (Wait-NordState -For Connected -TimeoutSec $TimeoutSec) {
        $st = Get-NordStatus -Quiet -Verify:$Verify
        if ($Verify -and $st.ExitCountry) { Write-Host ("OK  connected ({0}); edge exit = {1}" -f $st.Protocol, $st.ExitCountry) -ForegroundColor Green }
        else { Write-Host ("OK  connected via {0}" -f $st.Protocol) -ForegroundColor Green }
        return $st
    }
    Write-Host ("...  not confirmed connected within {0}s (run 'status')." -f $TimeoutSec) -ForegroundColor Yellow
}

# Disconnect. / 断开。
function Disconnect-Nord {
    [CmdletBinding()] param([ValidateSet('Cli','AppExe')][string]$Via = 'Cli', [switch]$NoWait, [int]$TimeoutSec = 15)
    Write-Host "-> --disconnect ..." -ForegroundColor Cyan
    Invoke-NordCli -Arguments @('--disconnect') -Via $Via
    if ($NoWait) { return }
    if (Wait-NordState -For Disconnected -TimeoutSec $TimeoutSec) { Write-Host "OK  disconnected" -ForegroundColor Green }
    else { Write-Host "...  still shows a Nord default route after ${TimeoutSec}s" -ForegroundColor Yellow }
}

# Reconnect = disconnect then connect (best or target). / 重连 = 先断开再连接（最优或指定目标）。
function Reconnect-Nord {
    [CmdletBinding(DefaultParameterSetName='Best')]
    param(
        [Parameter(ParameterSetName='Country', Position=0)][Alias('Group')][string]$Country,
        [Parameter(ParameterSetName='ServerName')][string]$ServerName,
        [Parameter(ParameterSetName='ServerId')][string]$ServerId,
        [ValidateSet('Cli','AppExe')][string]$Via = 'Cli',
        [switch]$Verify, [int]$TimeoutSec = 30
    )
    Disconnect-Nord -Via $Via -TimeoutSec 15
    $p = @{ Via = $Via; Verify = $Verify; TimeoutSec = $TimeoutSec }
    switch ($PSCmdlet.ParameterSetName) {
        'Country'    { Connect-Nord -Country $Country @p }
        'ServerName' { Connect-Nord -ServerName $ServerName @p }
        'ServerId'   { Connect-Nord -ServerId $ServerId @p }
        default      { Connect-Nord @p }
    }
}

# List Nord countries from the public API (read-only). / 从公开 API 列出 Nord 国家（只读）。
function Get-NordCountries {
    [CmdletBinding()] param([string]$Match)
    try { $c = Invoke-RestMethod 'https://api.nordvpn.com/v1/servers/countries' -TimeoutSec 10 }
    catch { Write-Warning "country list failed: $($_.Exception.Message)"; return }
    $c | Select-Object @{n='Country';e={$_.name}}, @{n='Code';e={$_.code}}, id |
        Where-Object { -not $Match -or $_.Country -match $Match } | Sort-Object Country
}

Export-ModuleMember -Function `
    Get-NordVpnExe, Get-NordVpnAppExe, Invoke-NordCli, ConvertTo-NordArgLine, `
    Get-NordActiveTunnel, Get-NordServerIpSet, Get-NordServerEndpoint, Get-NordExitViaEdge, `
    Get-NordStatus, Wait-NordState, Connect-Nord, Disconnect-Nord, Reconnect-Nord, Get-NordCountries
