<#
  nv.ps1  -  config-driven NordVPN launcher. / 配置驱动的 NordVPN 启动器。
  (Full bilingual command reference / 完整中英文命令参考: COMMANDS.md)

  Locations live in config.json (edit it freely). A location value can be:
  地点都存在 config.json（随意编辑），值可以是：
     "japan": "Japan"                     -> connect by country/group / 按国家或组连接
     "work":  { "server": "Japan #45" }   -> connect by server name   / 按服务器名连接
     "fast":  { "id": "12345" }           -> connect by server id     / 按服务器 id 连接

  Usage / 用法:
     .\nv.ps1                     status (default)
     .\nv.ps1 japan               connect to the 'japan' location from config
     .\nv.ps1 go japan            same thing (explicit)
     .\nv.ps1 Brazil              not in config -> connect directly to that country
     .\nv.ps1 go                  connect to defaultLocation
     .\nv.ps1 next                connect to the next location in 'favorites'
     .\nv.ps1 off                 disconnect
     .\nv.ps1 reconnect [name]    disconnect then reconnect (best or a location)
     .\nv.ps1 status [-Verify]    status (+ real exit if -Verify)
     .\nv.ps1 where               real exit country (through the tunnel)
     .\nv.ps1 list                show YOUR saved locations (config.json)
     .\nv.ps1 all [filter]        list ALL Nord countries (locations.json)
     .\nv.ps1 cities <country>    list a country's cities
     .\nv.ps1 refresh             (re)download the full country list
     .\nv.ps1 add <name> <country>     add/replace a location  (-AsServer / -AsId)
     .\nv.ps1 remove <name>            delete a location
     .\nv.ps1 fav                      show favorites
     .\nv.ps1 fav add <name>           save a favorite to config.json
     .\nv.ps1 fav remove <name>        remove a favorite
     .\nv.ps1 fav set <n1> <n2> ...    replace the whole favorites list
     .\nv.ps1 fav clear                empty favorites
     .\nv.ps1 help

  Options: -Verify  -DryRun (print the command, don't run)  -Via Cli|AppExe  -TimeoutSec <n>
  选项:    -Verify  -DryRun(只打印命令、不执行)  -Via Cli|AppExe  -TimeoutSec <n>
#>
[CmdletBinding()]
param(
    [Parameter(Position=0)][string]$Command,
    [Parameter(Position=1)][string]$Name,
    [Parameter(Position=2)][string]$Value,
    [switch]$Verify,
    [switch]$DryRun,
    [switch]$AsServer,
    [switch]$AsId,
    [int]$TimeoutSec = 0,
    [int]$MaxRuns = 0,
    [switch]$Force,
    [ValidateSet('Cli','AppExe')][string]$Via,
    [Parameter(Position=3, ValueFromRemainingArguments=$true)][string[]]$Rest
)

Import-Module (Join-Path $PSScriptRoot 'NordVpnCli.psm1') -Force -DisableNameChecking

$ConfigPath  = Join-Path $PSScriptRoot 'config.json'
$StatePath   = Join-Path $PSScriptRoot '.nv-state.json'
$CatalogPath = Join-Path $PSScriptRoot 'locations.json'

# ---- config load (create a default if missing) / 读取配置（缺失则创建默认） ----
if (-not (Test-Path $ConfigPath)) {
    @{
        defaultLocation = 'singapore'
        settings        = @{ via = 'Cli'; timeoutSec = 30; verifyByDefault = $false }
        favorites       = @('singapore','japan','us')
        locations       = [ordered]@{ singapore='Singapore'; japan='Japan'; us='United States' }
    } | ConvertTo-Json -Depth 6 | Set-Content $ConfigPath -Encoding UTF8
    Write-Host "Created default config.json" -ForegroundColor DarkGray
}
try { $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json }
catch { Write-Host "config.json is not valid JSON: $($_.Exception.Message)" -ForegroundColor Red; return }

# ---- effective settings (CLI option overrides config) / 生效设置（命令行参数覆盖配置） ----
$useVia     = if ($Via) { $Via } elseif ($cfg.settings.via) { $cfg.settings.via } else { 'Cli' }
$useTimeout = if ($TimeoutSec -gt 0) { $TimeoutSec } elseif ($cfg.settings.timeoutSec) { [int]$cfg.settings.timeoutSec } else { 30 }
$useVerify  = $Verify -or ($cfg.settings.verifyByDefault -eq $true)

function Get-LocNames { if ($cfg.locations) { $cfg.locations.PSObject.Properties.Name } else { @() } }

function Resolve-Location([string]$key) {
    $match = Get-LocNames | Where-Object { $_ -ieq $key } | Select-Object -First 1
    if (-not $match) { return $null }
    $v = $cfg.locations.$match
    if ($v -is [string]) { return @{ Name=$match; Group=$v } }
    $h = @{ Name = $match }
    if ($v.server) { $h.Server = $v.server }
    elseif ($v.id) { $h.Id = $v.id }
    elseif ($v.group) { $h.Group = $v.group }
    return $h
}

function Save-Config { $cfg | ConvertTo-Json -Depth 6 | Set-Content $ConfigPath -Encoding UTF8 }

# ---- full location catalog (locations.json, from Nord's public API) / 完整地点清单（来自 Nord 公开 API） ----
function Build-Catalog {
    Write-Host "downloading full country/city list from api.nordvpn.com ..." -ForegroundColor DarkGray
    try { $raw = Invoke-RestMethod 'https://api.nordvpn.com/v1/servers/countries' -TimeoutSec 25 }
    catch { Write-Host "download failed: $($_.Exception.Message)" -ForegroundColor Red; return }
    $countries = $raw | Sort-Object name | ForEach-Object {
        [pscustomobject]@{
            name = $_.name; code = $_.code; id = $_.id; serverCount = $_.serverCount
            cities = @($_.cities | Sort-Object name | ForEach-Object { [pscustomobject]@{ name = $_.name; id = $_.id; dnsName = $_.dns_name; serverCount = $_.serverCount } })
        }
    }
    [pscustomobject]@{ generated = (Get-Date).ToString('s'); source = 'api.nordvpn.com/v1/servers/countries'; count = @($countries).Count; countries = $countries } |
        ConvertTo-Json -Depth 6 | Set-Content $CatalogPath -Encoding UTF8
    Write-Host ("locations.json written: {0} countries, {1} cities" -f @($countries).Count, (@($countries.cities).Count)) -ForegroundColor Green
}
function Get-Catalog {
    if (-not (Test-Path $CatalogPath)) { return $null }
    try { return (Get-Content $CatalogPath -Raw | ConvertFrom-Json).countries } catch { return $null }
}
function Find-Country([string]$q) {
    $cat = Get-Catalog; if (-not $cat) { return $null }
    $m = $cat | Where-Object { $_.name -ieq $q -or $_.code -ieq $q } | Select-Object -First 1
    if (-not $m) { $m = $cat | Where-Object { $_.name -like "*$q*" } | Select-Object -First 1 }
    return $m
}
function Show-All([string]$filter) {
    $cat = Get-Catalog
    if (-not $cat) { Write-Host "No catalog yet - run:  .\nv.ps1 refresh" -ForegroundColor Yellow; return }
    $rows = $cat | Where-Object { -not $filter -or $_.name -match $filter -or $_.code -ieq $filter }
    Write-Host ("{0} of {1} Nord countries{2}:" -f @($rows).Count, @($cat).Count, $(if($filter){" matching '$filter'"})) -ForegroundColor Cyan
    $rows | ForEach-Object { Write-Host ("   {0,-26} {1,-4} cities:{2,-3} servers:{3}" -f $_.name, $_.code, @($_.cities).Count, $_.serverCount) }
}
function Show-Cities([string]$country) {
    $c = Find-Country $country
    if (-not $c) { Write-Host "country '$country' not found (try: .\nv.ps1 all $country)" -ForegroundColor Yellow; return }
    Write-Host ("{0} cities in {1}  (connect with the country name; per-city needs a server name/id):" -f @($c.cities).Count, $c.name) -ForegroundColor Cyan
    $c.cities | ForEach-Object { Write-Host ("   {0,-22} servers:{1}" -f $_.name, $_.serverCount) }
}

# ---- favorites (managed from the CLI, saved to config.json) / 收藏（命令行管理，写入 config.json） ----
function Get-Favs { if ($cfg.favorites) { @($cfg.favorites) } else { @() } }
function Set-Favs([string[]]$list) {
    $list = @($list)
    if ($cfg.PSObject.Properties.Name -contains 'favorites') { $cfg.favorites = $list }
    else { $cfg | Add-Member -NotePropertyName favorites -NotePropertyValue $list }
    Save-Config
}
function Show-Favs { $f = Get-Favs; if ($f.Count) { Write-Host ("favorites: " + ($f -join '  ->  ')) -ForegroundColor Cyan } else { Write-Host "no favorites set." -ForegroundColor DarkGray } }
function Test-KnownLocation([string]$n) { if (Resolve-Location $n) { return $true }; if (Find-Country $n) { return $true }; return $false }
function Invoke-Fav([string]$sub, [string]$val, [string[]]$more) {
    $op = if ($sub) { $sub.ToLower() } else { 'list' }
    switch ($op) {
        { $_ -in 'list','show','' } { Show-Favs }
        'add' {
            if (-not $val) { Write-Host "usage: nv.ps1 fav add <name>" -ForegroundColor Yellow; return }
            if (-not (Test-KnownLocation $val)) { Write-Host "note: '$val' isn't a saved preset or known country - saved anyway, but 'nv.ps1 $val' must resolve to connect." -ForegroundColor DarkGray }
            $f = @(Get-Favs)
            if ($f -contains $val) { Write-Host "'$val' is already a favorite." -ForegroundColor DarkGray }
            else { Set-Favs ($f + $val); Write-Host "saved '$val' to favorites (config.json)." -ForegroundColor Green }
            Show-Favs
        }
        { $_ -in 'remove','rm','delete' } {
            if (-not $val) { Write-Host "usage: nv.ps1 fav remove <name>" -ForegroundColor Yellow; return }
            Set-Favs (@(Get-Favs) | Where-Object { $_ -ne $val })
            Write-Host "removed '$val' from favorites." -ForegroundColor Green; Show-Favs
        }
        'set' {
            $list = @(); if ($val) { $list += $val }; if ($more) { $list += $more }
            if (-not $list.Count) { Write-Host "usage: nv.ps1 fav set <name> [name2 ...]" -ForegroundColor Yellow; return }
            Set-Favs $list; Write-Host "favorites saved (config.json)." -ForegroundColor Green; Show-Favs
        }
        'clear' { Set-Favs @(); Write-Host "favorites cleared." -ForegroundColor Green }
        default { Write-Host "usage: nv.ps1 fav [add <name> | remove <name> | set <names...> | clear]" -ForegroundColor Yellow }
    }
}

function Connect-Resolved($loc, [string]$label) {
    if ($DryRun) {
        $a = if ($loc.Server) { @('--connect','--server-name',$loc.Server) }
             elseif ($loc.Id) { @('--connect','--server-id',$loc.Id) }
             elseif ($loc.Group) { @('--connect','--group-name',$loc.Group) }
             else { @('--connect') }
        Write-Host ("[dry-run] {0}  ->  {1}" -f $label, (Invoke-NordCli -Arguments $a -Via $useVia -PassThruCommand)) -ForegroundColor DarkGray
        return
    }
    if ($loc.Name) { @{ last = $loc.Name } | ConvertTo-Json | Set-Content $StatePath -Encoding UTF8 }
    if     ($loc.Server) { Connect-Nord -ServerName $loc.Server -Via $useVia -Verify:$useVerify -TimeoutSec $useTimeout }
    elseif ($loc.Id)     { Connect-Nord -ServerId   $loc.Id     -Via $useVia -Verify:$useVerify -TimeoutSec $useTimeout }
    elseif ($loc.Group)  { Connect-Nord -Country    $loc.Group  -Via $useVia -Verify:$useVerify -TimeoutSec $useTimeout }
    else                 { Connect-Nord                          -Via $useVia -Verify:$useVerify -TimeoutSec $useTimeout }
}

# connect to a location by name: config preset, else catalog country, else raw country
# 按名字连接：先查 config 预设，再查 catalog 国家，最后当作原始国家名
function Go([string]$key) {
    if (-not $key) { $key = $cfg.defaultLocation }
    if (-not $key) { Write-Host "No location given and no defaultLocation in config." -ForegroundColor Yellow; return }
    $loc = Resolve-Location $key
    if ($loc) { Connect-Resolved $loc "config:$($loc.Name)"; return }
    $country = Find-Country $key
    if ($country) { Connect-Resolved @{ Group = $country.name; Name = $country.name } "catalog:$($country.name)"; return }
    Write-Host "'$key' is not in your config or the catalog - trying it as a raw country name." -ForegroundColor DarkGray
    Connect-Resolved @{ Group = $key } "direct:$key"
}

function Show-List {
    Write-Host "configured locations (config.json):" -ForegroundColor Cyan
    foreach ($n in (Get-LocNames | Sort-Object)) {
        $v = $cfg.locations.$n
        $disp = if ($v -is [string]) { $v } elseif ($v.server) { "server: $($v.server)" } elseif ($v.id) { "id: $($v.id)" } else { $v.group }
        $tag = if ($n -ieq $cfg.defaultLocation) { '  (default)' } else { '' }
        Write-Host ("   {0,-12} {1}{2}" -f $n, $disp, $tag)
    }
    if ($cfg.favorites) { Write-Host ("favorites: " + ($cfg.favorites -join ' -> ')) -ForegroundColor DarkGray }
}

function Get-NextFavorite {
    $favs = @($cfg.favorites)
    if ($favs.Count -eq 0) { return $null }
    $last = $null
    if (Test-Path $StatePath) { try { $last = (Get-Content $StatePath -Raw | ConvertFrom-Json).last } catch {} }
    $idx = [Array]::IndexOf($favs, $last)
    return $favs[($idx + 1) % $favs.Count]
}
function Go-Next {
    $next = Get-NextFavorite
    if (-not $next) { Write-Host "No 'favorites' in config." -ForegroundColor Yellow; return }
    Write-Host "next favorite -> $next" -ForegroundColor Cyan
    Go $next
}

# ---- scheduler (config.schedule) / 定时调度器（config.schedule） ----
function Show-Schedule {
    $sc = $cfg.schedule
    if (-not $sc) { Write-Host "no 'schedule' block in config.json" -ForegroundColor Yellow; return }
    Write-Host "schedule:" -ForegroundColor Cyan
    Write-Host ("   enabled        : {0}" -f $sc.enabled)
    Write-Host ("   mode           : {0}    (countdown | timeRange)" -f $sc.mode)
    Write-Host ("   reconnectMode  : {0}    (countdown only: favorite | fastest)" -f $sc.reconnectMode)
    Write-Host ("   countdownSec   : {0}" -f $sc.countdownSec)
    Write-Host ("   timeRange      : {0} - {1}" -f $sc.timeRangeStart, $sc.timeRangeEnd)
    Write-Host  "   run it with    : nv.ps1 schedule run    (foreground; Ctrl+C to stop)" -ForegroundColor DarkGray
    Write-Host  "   preview        : nv.ps1 schedule run -DryRun -MaxRuns 3" -ForegroundColor DarkGray
}
function Set-ScheduleEnabled([bool]$on) {
    if (-not $cfg.schedule) {
        $cfg | Add-Member -NotePropertyName schedule -NotePropertyValue ([pscustomobject]@{ enabled=$on; mode='countdown'; reconnectMode='favorite'; countdownSec=600; timeRangeStart='09:00'; timeRangeEnd='18:00' })
    } else { $cfg.schedule.enabled = $on }
    Save-Config
    Write-Host ("schedule turned {0}." -f $(if ($on) { 'ON' } else { 'OFF' })) -ForegroundColor Green
    Show-Schedule
}
function Test-InRange([string]$start, [string]$end) {
    try { $s = [datetime]::ParseExact($start,'HH:mm',$null); $e = [datetime]::ParseExact($end,'HH:mm',$null) } catch { return $true }
    $now = Get-Date
    $n = $now.Hour*60 + $now.Minute; $a = $s.Hour*60+$s.Minute; $b = $e.Hour*60+$e.Minute
    if ($a -le $b) { return ($n -ge $a -and $n -lt $b) } else { return ($n -ge $a -or $n -lt $b) }  # overnight range / 跨夜区间
}
function Invoke-ScheduleReconnect([bool]$dry) {
    if ("$($cfg.schedule.reconnectMode)" -ieq 'fastest') {
        if ($dry) { Write-Host ("   [{0}] reconnect -> fastest  (--disconnect; --connect best)" -f (Get-Date -Format HH:mm:ss)) -ForegroundColor DarkGray; return }
        Reconnect-Nord -Via $useVia -TimeoutSec $useTimeout | Out-Null
    } else {
        $next = Get-NextFavorite
        if (-not $next) { Write-Host "   no favorites set - add some (nv.ps1 fav add <name>) or use reconnectMode 'fastest'." -ForegroundColor Yellow; return }
        if ($dry) { Write-Host ("   [{0}] reconnect -> favorite '{1}'" -f (Get-Date -Format HH:mm:ss), $next) -ForegroundColor DarkGray; return }
        Go-Next
    }
}
function Invoke-Schedule([bool]$dry, [int]$maxRuns) {
    $sc = $cfg.schedule
    if (-not $sc) { Write-Host "no 'schedule' block in config.json" -ForegroundColor Yellow; return }
    $mode = "$($sc.mode)".ToLower().Replace('-','').Replace(' ','')
    Write-Host ("== schedule: mode={0}{1} ==" -f $sc.mode, $(if ($dry) { '  (DRY-RUN)' })) -ForegroundColor Cyan
    $runs = 0
    if ($mode -eq 'countdown') {
        $sec = [int]$sc.countdownSec; if ($sec -lt 15) { $sec = 15 }
        if ($sec -lt 60) { Write-Host "   note: short interval ($sec s) - frequent reconnects stress Nord servers; consider >= 60." -ForegroundColor DarkYellow }
        Write-Host ("countdown: every {0}s -> reconnect ({1}).  Ctrl+C to stop." -f $sec, $sc.reconnectMode)
        while ($true) {
            Invoke-ScheduleReconnect $dry
            $runs++; if ($maxRuns -gt 0 -and $runs -ge $maxRuns) { break }
            Start-Sleep -Seconds $(if ($dry) { [Math]::Min(2, $sec) } else { $sec })
        }
    } elseif ($mode -eq 'timerange') {
        Write-Host ("time range: connected {0}-{1} (to '{2}'), disconnected outside.  Ctrl+C to stop." -f $sc.timeRangeStart, $sc.timeRangeEnd, $cfg.defaultLocation)
        while ($true) {
            $inRange = Test-InRange $sc.timeRangeStart $sc.timeRangeEnd
            $active  = [bool](Get-NordActiveTunnel)
            $stamp   = Get-Date -Format HH:mm:ss
            if ($inRange -and -not $active)      { if ($dry) { Write-Host "   [$stamp] in range, not connected -> would CONNECT ($($cfg.defaultLocation))" -ForegroundColor DarkGray } else { Go $cfg.defaultLocation } }
            elseif (-not $inRange -and $active)  { if ($dry) { Write-Host "   [$stamp] out of range, connected -> would DISCONNECT" -ForegroundColor DarkGray } else { Disconnect-Nord -Via $useVia } }
            else                                 { Write-Host ("   [$stamp] inRange={0} active={1} (no change)" -f $inRange, $active) -ForegroundColor DarkGray }
            $runs++; if ($maxRuns -gt 0 -and $runs -ge $maxRuns) { break }
            Start-Sleep -Seconds $(if ($dry) { 2 } else { 30 })
        }
    } else {
        Write-Host "unknown schedule.mode '$($sc.mode)' - use 'countdown' or 'timeRange'." -ForegroundColor Yellow
    }
    Write-Host "schedule stopped." -ForegroundColor DarkGray
}

function Show-Help {
    Write-Host @'

NordVPN CLI (nv.ps1) - config-driven launcher.   Full reference: COMMANDS.md

CONNECT / SWITCH
  nv.ps1                       status (default, no args)
  nv.ps1 <name>                connect: your preset -> catalog country -> raw country
  nv.ps1 go [name]             connect to name, or to defaultLocation
  nv.ps1 next                  connect to the next favorite (cycles)
  nv.ps1 reconnect [name]      disconnect then reconnect (best or name)
  nv.ps1 off                   disconnect              (aliases: disconnect, down)

STATUS
  nv.ps1 status [-Verify]      protocol + tunnel + server (-Verify = real exit)  (alias: st)
  nv.ps1 where                 real exit country, checked through msedge

BROWSE LOCATIONS
  nv.ps1 list                  your saved presets (config.json)                 (alias: ls)
  nv.ps1 all [filter]          all Nord countries (locations.json)              (alias: countries)
  nv.ps1 cities <country>      a country's cities
  nv.ps1 refresh               re-download the full country list

PRESETS  (config.json "locations")
  nv.ps1 add <name> <country>          save a preset
  nv.ps1 add <name> <val> -AsServer    save by server name (e.g. "Japan #45")
  nv.ps1 add <name> <val> -AsId        save by server id
  nv.ps1 remove <name>                 delete a preset                          (alias: rm)

FAVORITES  (config.json "favorites" - written to file)
  nv.ps1 fav                   list favorites
  nv.ps1 fav add <name>        save a favorite
  nv.ps1 fav remove <name>     remove one
  nv.ps1 fav set <a> <b> ...   replace the whole list
  nv.ps1 fav clear             empty it

SCHEDULE  (config.json "schedule")
  nv.ps1 schedule              show schedule settings
  nv.ps1 schedule on | off     enable / disable
  nv.ps1 schedule run          run it (foreground, Ctrl+C to stop)
  nv.ps1 schedule run -DryRun -MaxRuns 3    preview without connecting
    countdown mode : every countdownSec, reconnect (favorite=cycle / fastest=best)
    timeRange mode : connected between timeRangeStart-End (to defaultLocation), else off

OPTIONS (append to any command)
  -Verify           confirm real exit via msedge (status / connect / reconnect)
  -DryRun           print the NordVPN.exe command instead of running it
  -Via Cli|AppExe   which exe to use (default Cli = NordVPN.exe)
  -TimeoutSec <n>   wait time for connect / disconnect
  -AsServer | -AsId with 'add', store as server name / id

NOTE: NordVPN's CLI has no protocol/city flag - 'connect' uses the app's protocol;
      location = country/group, server name, or id.  Details: COMMANDS.md
'@
}

# ---- dispatch (route the command word to an action) / 分发（把命令词路由到动作） ----
$c = if ($Command) { $Command.ToLower() } else { 'status' }
switch ($c) {
    'status'     { Get-NordStatus -Verify:$useVerify | Out-Null }
    'st'         { Get-NordStatus -Verify:$useVerify | Out-Null }
    'where'      { $e = Get-NordExitViaEdge; if ($e) { Write-Host ("exit: {0}  {1}{2}  [{3}]" -f $e.Ip,$e.Country,$(if($e.City){", $($e.City)"}),$e.Org) -ForegroundColor Green } else { Write-Host "could not determine exit via msedge" -ForegroundColor Yellow } }
    'list'       { Show-List }
    'ls'         { Show-List }
    'all'        { Show-All $Name }
    'countries'  { Show-All $Name }
    'cities'     { if ($Name) { Show-Cities $Name } else { Write-Host "usage: nv.ps1 cities <country>" -ForegroundColor Yellow } }
    'refresh'    { Build-Catalog }
    'fav'        { Invoke-Fav $Name $Value $Rest }
    'favorites'  { Invoke-Fav $Name $Value $Rest }
    'schedule'   {
        $sub = if ($Name) { $Name.ToLower() } else { 'status' }
        switch ($sub) {
            { $_ -in 'status','show','' } { Show-Schedule }
            'on'  { Set-ScheduleEnabled $true }
            'off' { Set-ScheduleEnabled $false }
            { $_ -in 'run','start' } {
                if (-not $cfg.schedule) { Write-Host "no 'schedule' block in config.json" -ForegroundColor Yellow; break }
                if (-not $cfg.schedule.enabled -and -not $Force -and -not $DryRun) {
                    Write-Host "schedule is OFF. enable it:  nv.ps1 schedule on   (or use -Force / -DryRun to run once anyway)" -ForegroundColor Yellow; break
                }
                Invoke-Schedule ([bool]$DryRun) $MaxRuns
            }
            default { Write-Host "usage: nv.ps1 schedule [status | on | off | run]   (run: -DryRun -MaxRuns <n> -Force)" -ForegroundColor Yellow }
        }
    }
    'sched'      { & $PSCommandPath schedule $Name -DryRun:$DryRun -MaxRuns $MaxRuns -Force:$Force }
    'go'         { Go $Name }
    'next'       { Go-Next }
    'off'        { Disconnect-Nord -Via $useVia }
    'disconnect' { Disconnect-Nord -Via $useVia }
    'down'       { Disconnect-Nord -Via $useVia }
    'reconnect'  {
        if ($Name) { $loc = Resolve-Location $Name; if (-not $loc) { $loc = @{ Group = $Name } }
                     Disconnect-Nord -Via $useVia -TimeoutSec 15; Connect-Resolved $loc "reconnect:$Name" }
        else       { Reconnect-Nord -Via $useVia -Verify:$useVerify -TimeoutSec $useTimeout }
    }
    'add' {
        if (-not $Name -or -not $Value) { Write-Host "usage: nv.ps1 add <name> <country>   [-AsServer | -AsId]" -ForegroundColor Yellow; break }
        $entry = if ($AsServer) { @{ server = $Value } } elseif ($AsId) { @{ id = $Value } } else { $Value }
        if (-not $cfg.locations) { $cfg | Add-Member -NotePropertyName locations -NotePropertyValue ([pscustomobject]@{}) }
        $cfg.locations | Add-Member -NotePropertyName $Name -NotePropertyValue $entry -Force
        Save-Config; Write-Host "added '$Name'." -ForegroundColor Green; Show-List
    }
    'remove' {
        if (-not $Name) { Write-Host "usage: nv.ps1 remove <name>" -ForegroundColor Yellow; break }
        if ($cfg.locations.PSObject.Properties.Name -contains $Name) { $cfg.locations.PSObject.Properties.Remove($Name); Save-Config; Write-Host "removed '$Name'." -ForegroundColor Green; Show-List }
        else { Write-Host "'$Name' not found." -ForegroundColor Yellow }
    }
    'rm'         { & $PSCommandPath remove $Name }
    'help'       { Show-Help }
    '-h'         { Show-Help }
    '--help'     { Show-Help }
    default      {
        # bare name: treat $Command as a location (config preset or raw country)
        # 裸名字:把 $Command 当作一个地点(config 预设或原始国家名)
        Go $Command
    }
}
