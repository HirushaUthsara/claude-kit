<#
.SYNOPSIS
  Optional CPU load test: keeps every logical CPU busy for -Seconds and records sustained
  clock speed and throttling. Changes nothing. Ask the user first, and suggest AC power.
.PARAMETER Seconds
  Load duration (default 120). Stops automatically.
.PARAMETER OutFile
  Path for the JSON output. Prints to stdout if omitted.
#>
param([int]$Seconds = 120, [string]$OutFile)
$ErrorActionPreference = 'SilentlyContinue'
function Num($v, [int]$d = 1) { if ($null -eq $v) { $null } else { [math]::Round([double]$v, $d) } }
function Pi { Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'" }   # language-neutral

$threads = (Get-CimInstance Win32_Processor | Measure-Object NumberOfLogicalProcessors -Sum).Sum
$bat = Get-CimInstance Win32_Battery | Select-Object -First 1
$ov  = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
$names = @{ '961cc777-2547-4f9d-8174-7d86181b8a7a' = 'Best power efficiency'; '00000000-0000-0000-0000-000000000000' = 'Balanced'; 'ded574b5-45a0-4f42-8737-46345c09c238' = 'Best performance' }
$onAC = (-not $bat) -or ($bat.BatteryStatus -eq 2)
$g = if ($onAC) { $ov.ActiveOverlayAcPowerScheme } else { $ov.ActiveOverlayDcPowerScheme }
$mode = if (-not $g) { 'Balanced (default)' } elseif ($names.ContainsKey([string]$g)) { $names[[string]$g] } else { [string]$g }

$baseMHz = (Pi).ProcessorFrequency
$idle = @(1..3 | ForEach-Object { (Pi).PercentProcessorPerformance; Start-Sleep -Seconds 2 })
$t0 = Get-Date

# one runspace per logical CPU, in this process (lighter than background jobs)
$pool = [runspacefactory]::CreateRunspacePool(1, $threads); $pool.Open()
$workers = foreach ($i in 1..$threads) {
    $ps = [powershell]::Create(); $ps.RunspacePool = $pool
    [void]$ps.AddScript({ param($sec) $end = (Get-Date).AddSeconds($sec); $x = 0.0; while ((Get-Date) -lt $end) { for ($k = 0; $k -lt 200000; $k++) { $x += [math]::Sqrt($k) } } }).AddArgument($Seconds)
    [pscustomobject]@{ ps = $ps; handle = $ps.BeginInvoke() }
}
Start-Sleep -Seconds 3
$rows = @()
while (((Get-Date) - $t0).TotalSeconds -lt $Seconds) {
    $p = Pi
    $rows += [ordered]@{ sec = [int]((Get-Date) - $t0).TotalSeconds; cpuPct = $p.PercentProcessorTime; perfPct = $p.PercentProcessorPerformance
                         mhz = [int]($p.PercentProcessorPerformance * $baseMHz / 100); perfLimitPct = $p.PercentPerformanceLimit }
    Start-Sleep -Seconds 4
}
foreach ($w in $workers) { try { $w.ps.EndInvoke($w.handle) } catch {}; $w.ps.Dispose() }
$pool.Close(); $pool.Dispose()

$load = @($rows | Where-Object { $_.cpuPct -ge 90 })
function Avg($r, $k) { if (@($r).Count) { Num ((@($r) | ForEach-Object { $_[$k] } | Measure-Object -Average).Average) 0 } else { $null } }
$throttle = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Processor-Power'; StartTime = $t0 } -ErrorAction SilentlyContinue)
$res = [ordered]@{
    schema = 'windows-perf-diagnosis/load@1'; testedAt = $t0.ToString('s'); seconds = $Seconds; threads = $threads
    powerSource = if ($onAC) { 'AC' } else { "Battery ($($bat.EstimatedChargeRemaining)%)" }; powerMode = $mode
    baseMHz = $baseMHz; idlePerfPct = Num (($idle | Measure-Object -Average).Average) 0
    underLoad = [ordered]@{
        samples = $load.Count; avgCpuPct = Avg $load 'cpuPct'; avgMHz = Avg $load 'mhz'
        minMHz = if ($load.Count) { ($load | ForEach-Object { $_.mhz } | Measure-Object -Minimum).Minimum } else { $null }
        maxMHz = if ($load.Count) { ($load | ForEach-Object { $_.mhz } | Measure-Object -Maximum).Maximum } else { $null }
        first20sAvgMHz = Avg ($load | Select-Object -First 5) 'mhz'
        last30sAvgMHz  = Avg ($load | Select-Object -Last 7) 'mhz'
        minPerfLimitPct = if ($load.Count) { ($load | ForEach-Object { $_.perfLimitPct } | Measure-Object -Minimum).Minimum } else { $null }
    }
    throttleEvents = $throttle.Count
    samples = $rows
}
$json = $res | ConvertTo-Json -Depth 5
if ($OutFile) { [IO.File]::WriteAllText($OutFile, $json, (New-Object Text.UTF8Encoding($false))); "Load test written to $OutFile" } else { $json }
