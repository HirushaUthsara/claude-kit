<#
.SYNOPSIS
  Read-only network performance test. Changes no settings and does not flush caches.
.PARAMETER Pings
  Pings per target (default 30, ~6 s each).
.PARAMETER SkipThroughput
  Skip the download/upload tests. Use on mobile data, phone hotspots or capped plans:
  the throughput + loaded-latency tests transfer roughly 25-40 MB.
.PARAMETER OutFile
  Path for the JSON output. Prints to stdout if omitted.
#>
param([int]$Pings = 30, [switch]$SkipThroughput, [string]$OutFile)
$ErrorActionPreference = 'SilentlyContinue'
function Num($v, [int]$d = 1) { if ($null -eq $v) { $null } else { [math]::Round([double]$v, $d) } }

function Ping-Stats([string]$target, [int]$n) {
    $p = New-Object System.Net.NetworkInformation.Ping
    $times = New-Object System.Collections.Generic.List[double]; $lost = 0
    for ($i = 0; $i -lt $n; $i++) {
        try { $r = $p.Send($target, 2000); if ($r.Status -eq 'Success') { $times.Add($r.RoundtripTime) } else { $lost++ } } catch { $lost++ }
        Start-Sleep -Milliseconds 200
    }
    $s = @($times | Sort-Object)
    $jit = $null
    if ($times.Count -gt 1) { $d = for ($i = 1; $i -lt $times.Count; $i++) { [math]::Abs($times[$i] - $times[$i - 1]) }; $jit = Num (($d | Measure-Object -Average).Average) }
    [ordered]@{
        target = $target; sent = $n; lossPct = Num (100 * $lost / $n)
        minMs = if ($s.Count) { $s[0] } else { $null }
        medianMs = if ($s.Count) { $s[[int][math]::Floor($s.Count / 2)] } else { $null }
        p95Ms = if ($s.Count) { $s[[int][math]::Max(0, [math]::Ceiling($s.Count * 0.95) - 1)] } else { $null }
        maxMs = if ($s.Count) { $s[-1] } else { $null }
        jitterMs = $jit
    }
}

function Dns-Times([string]$server, [string[]]$names) {
    $t = foreach ($n in $names) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        try { Resolve-DnsName -Name $n -Type A -Server $server -DnsOnly -NoHostsFile -QuickTimeout -ErrorAction Stop | Out-Null; $sw.ElapsedMilliseconds } catch { $null }
    }
    $ok = @($t | Where-Object { $null -ne $_ })
    [ordered]@{ server = $server; timesMs = @($t); failures = ($names.Count - $ok.Count); avgMs = if ($ok.Count) { Num (($ok | Measure-Object -Average).Average) 0 } else { $null } }
}

function Download-Mbps([string]$url) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $w = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 180 -ErrorAction Stop; $sw.Stop()
        [ordered]@{ url = $url; ok = $true; mbps = Num (($w.RawContentLength * 8 / 1e6) / $sw.Elapsed.TotalSeconds) 2; seconds = Num $sw.Elapsed.TotalSeconds; mb = Num ($w.RawContentLength / 1MB) }
    } catch { [ordered]@{ url = $url; ok = $false; error = "$($_.Exception.Message)".Substring(0, [Math]::Min(100, "$($_.Exception.Message)".Length)) } }
}

# ---- connection ----
$route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1
if (-not $route) { $res = [ordered]@{ schema = 'windows-perf-diagnosis/network@1'; connected = $false }; $j = $res | ConvertTo-Json; if ($OutFile) { [IO.File]::WriteAllText($OutFile, $j) } else { $j }; return }
$a = Get-NetAdapter -InterfaceIndex $route.ifIndex
$sysDns = @((Get-DnsClientServerAddress -InterfaceIndex $route.ifIndex -AddressFamily IPv4).ServerAddresses)
$conn = [ordered]@{
    adapter = $a.Name; description = $a.InterfaceDescription; linkSpeed = $a.LinkSpeed; gateway = $route.NextHop; dnsServers = $sysDns
    mtu = (Get-NetIPInterface -InterfaceIndex $route.ifIndex -AddressFamily IPv4).NlMtu
    ipv6 = [bool](Get-NetIPAddress -InterfaceIndex $route.ifIndex -AddressFamily IPv6 -PrefixOrigin RouterAdvertisement)
    proxyEnabled = [bool](Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings').ProxyEnable
    vpnAdapterUp = [bool](Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -match 'TAP|VPN|WireGuard|Tunnel|Wintun' })
    tcpAutoTuning = "$((Get-NetTCPSetting -SettingName Internet).AutoTuningLevelLocal)"
    hint = if ($route.NextHop -like '172.20.10.*') { 'iPhone Personal Hotspot subnet' } elseif ($route.NextHop -like '192.168.43.*') { 'Android hotspot subnet' } elseif ($a.InterfaceDescription -match 'Remote NDIS|RNDIS') { 'USB tethering / USB modem (RNDIS)' } else { $null }
}
$wl = netsh wlan show interfaces 2>$null | Out-String
if ($a.InterfaceDescription -match 'Wi-?Fi|Wireless|802\.11|WLAN' -and $wl) {
    $w = [ordered]@{}
    foreach ($f in 'Band', 'Channel', 'Radio type', 'Receive rate \(Mbps\)', 'Transmit rate \(Mbps\)', 'Signal') {
        $m = [regex]::Match($wl, "(?m)^\s*$f\s*:\s*(.+)$"); if ($m.Success) { $w[($f -replace ' \\\(Mbps\\\)', '' -replace ' ', '')] = $m.Groups[1].Value.Trim() }
    }
    $nets = netsh wlan show networks mode=bssid 2>$null | Out-String
    $ch = @([regex]::Matches($nets, '(?m)^\s*Channel\s*:\s*(\d+)') | ForEach-Object { [int]$_.Groups[1].Value })
    $w.visibleAPs = $ch.Count
    $w.busiestChannels = @($ch | Group-Object | Sort-Object Count -Descending | Select-Object -First 3 | ForEach-Object { "ch $($_.Name): $($_.Count)" })
    $conn.wifi = $w
}
$st = Get-NetAdapterStatistics -Name $a.Name
$conn.adapterErrors = [ordered]@{ rxErrors = $st.ReceivedPacketErrors; rxDiscards = $st.ReceivedDiscardedPackets; txErrors = $st.OutboundPacketErrors }

# ---- latency: local link vs internet ----
$latency = @( (Ping-Stats $route.NextHop $Pings), (Ping-Stats '1.1.1.1' $Pings), (Ping-Stats '8.8.8.8' $Pings) )

# ---- DNS: current resolver vs public resolvers (queried directly; local cache untouched) ----
$names = 'github.com', 'www.google.com', 'www.wikipedia.org', 'www.youtube.com', 'www.microsoft.com'
$dns = @()
foreach ($s in (@($sysDns | Select-Object -First 1) + '1.1.1.1', '8.8.8.8' | Select-Object -Unique)) { if ($s) { $dns += Dns-Times $s $names } }

# ---- TCP connect time ----
$tcp = foreach ($h in 'www.google.com', 'github.com', 'www.cloudflare.com') {
    $c = New-Object Net.Sockets.TcpClient; $sw = [Diagnostics.Stopwatch]::StartNew()
    try { $c.Connect($h, 443); [ordered]@{ host = $h; ms = $sw.ElapsedMilliseconds } } catch { [ordered]@{ host = $h; ms = $null; error = 'failed' } } finally { $c.Close() }
}

# ---- throughput + loaded latency ----
$throughput = $null; $loaded = $null
if (-not $SkipThroughput) {
    $dl = @()
    foreach ($u in 'https://speed.cloudflare.com/__down?bytes=10000000', 'https://proof.ovh.net/files/10Mb.dat', 'http://speedtest.tele2.net/10MB.zip') {
        $dl += Download-Mbps $u
        if (@($dl | Where-Object ok).Count -ge 2) { break }   # two good measurements are enough
    }
    $up = $null
    $body = New-Object byte[] 5000000; (New-Object Random).NextBytes($body)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try { Invoke-WebRequest -Uri 'https://speed.cloudflare.com/__up' -Method Post -Body $body -ContentType 'application/octet-stream' -UseBasicParsing -TimeoutSec 180 -ErrorAction Stop | Out-Null; $sw.Stop()
          $up = [ordered]@{ ok = $true; mbps = Num ((5e6 * 8 / 1e6) / $sw.Elapsed.TotalSeconds) 2; seconds = Num $sw.Elapsed.TotalSeconds } }
    catch { $up = [ordered]@{ ok = $false; error = "$($_.Exception.Message)".Substring(0, [Math]::Min(100, "$($_.Exception.Message)".Length)) } }
    $okDl = @($dl | Where-Object ok | ForEach-Object { $_.mbps })
    $throughput = [ordered]@{ downloads = $dl; downloadMbpsBest = if ($okDl.Count) { ($okDl | Measure-Object -Maximum).Maximum } else { $null }; upload = $up }

    # latency while a download saturates the link (bufferbloat)
    $job = Start-Job { try { Invoke-WebRequest 'https://speed.cloudflare.com/__down?bytes=20000000' -UseBasicParsing -TimeoutSec 90 | Out-Null } catch {} }
    Start-Sleep -Seconds 2
    $loaded = Ping-Stats '1.1.1.1' 20
    $job | Stop-Job; $job | Remove-Job -Force
}

$res = [ordered]@{
    schema = 'windows-perf-diagnosis/network@1'; testedAt = (Get-Date).ToString('s'); connected = $true
    connection = $conn; latency = $latency; dns = $dns; tcpConnect = @($tcp)
    throughput = $throughput; latencyUnderLoad = $loaded; throughputSkipped = [bool]$SkipThroughput
}
$json = $res | ConvertTo-Json -Depth 6
if ($OutFile) { [IO.File]::WriteAllText($OutFile, $json, (New-Object Text.UTF8Encoding($false))); "Network results written to $OutFile" } else { $json }
