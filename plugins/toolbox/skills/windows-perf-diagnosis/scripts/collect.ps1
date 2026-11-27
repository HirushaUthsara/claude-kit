<#
.SYNOPSIS
  Read-only Windows performance and health snapshot. Changes nothing, needs no admin.
.PARAMETER Samples
  Number of live performance samples, 4 seconds apart (default 10, ~40 s).
.PARAMETER OutFile
  Path for the JSON output. Prints to stdout if omitted.
#>
param([int]$Samples = 10, [string]$OutFile)

$ErrorActionPreference = 'SilentlyContinue'
$notChecked = New-Object System.Collections.Generic.List[string]

function Short($text, [int]$n = 160) {
    if (-not $text) { return $null }
    $t = ($text -replace '\s+', ' ').Trim()
    $t.Substring(0, [Math]::Min($n, $t.Length))
}
function Num($v, [int]$d = 1) { if ($null -eq $v) { $null } else { [math]::Round([double]$v, $d) } }
function Dt($d, $fmt = 's') { if ($d) { $d.ToString($fmt) } else { $null } }

$os   = Get-CimInstance Win32_OperatingSystem
$cs   = Get-CimInstance Win32_ComputerSystem
$cv   = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
$bios = Get-CimInstance Win32_BIOS
$boot = $os.LastBootUpTime
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ---------------- system ----------------
$system = [ordered]@{
    collectedAt       = (Get-Date).ToString('s')
    elevated          = $isAdmin
    manufacturer      = $cs.Manufacturer
    model             = $cs.Model
    os                = $os.Caption
    build             = "$($cv.CurrentBuild).$($cv.UBR)"
    displayVersion    = $cv.DisplayVersion
    installDate       = Dt $os.InstallDate 'yyyy-MM-dd'
    lastBoot          = Dt $boot
    uptimeHours       = Num (((Get-Date) - $boot).TotalHours)
    cpu               = ($cpu.Name -replace '\s+', ' ').Trim()
    cores             = $cpu.NumberOfCores
    threads           = $cpu.NumberOfLogicalProcessors
    biosVersion       = $bios.SMBIOSBIOSVersion
    biosDate          = Dt $bios.ReleaseDate 'yyyy-MM-dd'
    hypervisorPresent = $cs.HypervisorPresent
}

# ---------------- power ----------------
$bat = Get-CimInstance Win32_Battery | Select-Object -First 1
$ov  = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
$modeNames = @{
    '961cc777-2547-4f9d-8174-7d86181b8a7a' = 'Best power efficiency'
    '00000000-0000-0000-0000-000000000000' = 'Balanced'
    'ded574b5-45a0-4f42-8737-46345c09c238' = 'Best performance'
}
function ModeName($g) { if (-not $g) { 'Balanced (default)' } elseif ($modeNames.ContainsKey([string]$g)) { $modeNames[[string]$g] } else { [string]$g } }
$usbSS = powercfg /query SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 2>$null
$usbHex = @([regex]::Matches(($usbSS -join "`n"), '0x0000000([01])') | ForEach-Object { $_.Groups[1].Value })
$power = [ordered]@{
    source                  = if (-not $bat) { 'AC (no battery)' } elseif ($bat.BatteryStatus -eq 2) { 'AC' } else { 'Battery' }
    batteryPercent          = $bat.EstimatedChargeRemaining
    powerPlan               = ((powercfg /getactivescheme) -replace '.*\((.*)\).*', '$1')
    modeOnAC                = ModeName $ov.ActiveOverlayAcPowerScheme
    modeOnBattery           = ModeName $ov.ActiveOverlayDcPowerScheme
    usbSelectiveSuspendAC   = if ($usbHex.Count -ge 2) { $usbHex[-2] -eq '1' } else { $null }
    usbSelectiveSuspendDC   = if ($usbHex.Count -ge 1) { $usbHex[-1] -eq '1' } else { $null }
}

# ---------------- memory ----------------
$pfu = @(Get-CimInstance Win32_PageFileUsage)
$mm  = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
$memory = [ordered]@{
    totalGB                  = Num ($cs.TotalPhysicalMemory / 1GB) 2
    modules                  = @(Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
                                  [ordered]@{ slot = $_.DeviceLocator; gb = Num ($_.Capacity / 1GB); configuredMHz = $_.ConfiguredClockSpeed; ratedMHz = $_.Speed; partNumber = ("$($_.PartNumber)").Trim() } })
    smbiosReportedSlots      = (Get-CimInstance Win32_PhysicalMemoryArray | Select-Object -First 1).MemoryDevices
    commitUsedGB             = Num (($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) / 1MB) 2
    commitLimitGB            = Num ($os.TotalVirtualMemorySize / 1MB) 2
    commitPct                = Num (100 * ($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) / $os.TotalVirtualMemorySize)
    pagefiles                = @($pfu | ForEach-Object { [ordered]@{ path = $_.Name; allocatedMB = $_.AllocatedBaseSize; usedMB = $_.CurrentUsage; peakMB = $_.PeakUsage } })
    pagefileAutoManaged      = $cs.AutomaticManagedPagefile
    disablePagingExecutive   = $mm.DisablePagingExecutive
    sysMainStatus            = "$((Get-Service SysMain).Status)"
    memoryCompressionRunning = [bool](Get-Process -Name 'Memory Compression')
    memoryCompressionMB      = Num ((Get-Process -Name 'Memory Compression').WorkingSet64 / 1MB) 0
}
# Kernel pools (driver memory). Language-neutral CIM class, no admin needed.
$pm = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory
$memory.kernelNonpagedPoolMB = Num ($pm.PoolNonpagedBytes / 1MB) 0
$memory.kernelPagedPoolMB    = Num ($pm.PoolPagedBytes / 1MB) 0

# ---------------- battery ----------------
$battery = $null
if ($bat) {
    $design = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData | Select-Object -First 1).DesignedCapacity
    $full   = (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity | Select-Object -First 1).FullChargedCapacity
    $cycles = (Get-CimInstance -Namespace root\wmi -ClassName BatteryCycleCount | Select-Object -First 1).CycleCount
    if (-not ($design -and $full)) {
        # Fallback: powercfg's XML battery report, written to a temp file and deleted straight away.
        $tmp = Join-Path $env:TEMP ("wpd-battery-{0}.xml" -f [guid]::NewGuid().ToString('N'))
        powercfg /batteryreport /xml /output $tmp 2>$null | Out-Null
        if (Test-Path $tmp) {
            try { [xml]$bx = Get-Content $tmp -Raw; $b0 = @($bx.BatteryReport.Batteries.Battery)[0]
                  $design = [double]$b0.DesignCapacity; $full = [double]$b0.FullChargeCapacity; if (-not $cycles) { $cycles = $b0.CycleCount } } catch {}
            Remove-Item -LiteralPath $tmp -Force
        }
    }
    $battery = [ordered]@{
        designCapacity_mWh     = $design
        fullChargeCapacity_mWh = $full
        healthPct              = if ($design -and $full) { Num (100 * $full / $design) 0 } else { $null }
        cycleCount             = $cycles
    }
    if (-not $battery.healthPct) { $notChecked.Add('Battery wear (capacity data unavailable)') }
}

# ---------------- live samples ----------------
# English counter paths first (precise disk latency); CIM classes as a language-neutral fallback.
$samplesOut = @()
$ctr = '\Processor(_Total)\% Processor Time', '\System\Processor Queue Length', '\Processor Information(_Total)\% Processor Performance',
       '\Memory\Available MBytes', '\Memory\Pages/sec', '\PhysicalDisk(_Total)\% Idle Time',
       '\PhysicalDisk(_Total)\Avg. Disk sec/Read', '\PhysicalDisk(_Total)\Avg. Disk sec/Write'
$sets = Get-Counter -Counter $ctr -SampleInterval 4 -MaxSamples $Samples -ErrorAction SilentlyContinue
if ($sets -and @($sets).Count -gt 0 -and @($sets)[0].CounterSamples.Count -ge 8) {
    foreach ($s in $sets) {
        $v = $s.CounterSamples
        $samplesOut += [ordered]@{
            t = $s.Timestamp.ToString('HH:mm:ss'); cpuPct = Num $v[0].CookedValue 0; runQueue = $v[1].CookedValue
            cpuPerfPct = Num $v[2].CookedValue 0; availMB = Num $v[3].CookedValue 0; pagesPerSec = Num $v[4].CookedValue 0
            diskIdlePct = Num $v[5].CookedValue 0; diskReadMs = Num ($v[6].CookedValue * 1000) 2; diskWriteMs = Num ($v[7].CookedValue * 1000) 2
        }
    }
} else {
    $notChecked.Add('Disk latency (English performance counters unavailable; used CIM fallback for CPU/memory)')
    for ($i = 0; $i -lt $Samples; $i++) {
        $p  = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'"
        $sy = Get-CimInstance Win32_PerfFormattedData_PerfOS_System
        $pi = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'"
        $me = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory
        $dk = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'"
        $samplesOut += [ordered]@{
            t = (Get-Date).ToString('HH:mm:ss'); cpuPct = $p.PercentProcessorTime; runQueue = $sy.ProcessorQueueLength
            cpuPerfPct = $pi.PercentProcessorPerformance; availMB = $me.AvailableMBytes; pagesPerSec = $me.PagesPersec
            diskIdlePct = $dk.PercentIdleTime; diskReadMs = $null; diskWriteMs = $null
        }
        if ($i -lt $Samples - 1) { Start-Sleep -Seconds 4 }
    }
}
function Stat($rows, $key) {
    $vals = @($rows | ForEach-Object { $_[$key] } | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ } | Sort-Object)
    if ($vals.Count -eq 0) { return $null }
    [ordered]@{ avg = Num (($vals | Measure-Object -Average).Average); median = $vals[[int][math]::Floor($vals.Count / 2)]; min = $vals[0]; max = $vals[-1] }
}
$live = [ordered]@{
    samples = $samplesOut
    summary = [ordered]@{
        cpuPct = Stat $samplesOut 'cpuPct'; runQueue = Stat $samplesOut 'runQueue'; cpuPerfPct = Stat $samplesOut 'cpuPerfPct'
        availMB = Stat $samplesOut 'availMB'; pagesPerSec = Stat $samplesOut 'pagesPerSec'; diskIdlePct = Stat $samplesOut 'diskIdlePct'
        diskReadMs = Stat $samplesOut 'diskReadMs'; diskWriteMs = Stat $samplesOut 'diskWriteMs'
    }
}

# ---------------- processes ----------------
$procs = Get-Process
$topMemory = @($procs | Group-Object ProcessName | ForEach-Object {
        [ordered]@{ name = $_.Name; count = $_.Count
            privateMB = Num ((($_.Group | Measure-Object PrivateMemorySize64 -Sum).Sum) / 1MB) 0
            workingSetMB = Num ((($_.Group | Measure-Object WorkingSet64 -Sum).Sum) / 1MB) 0 } } |
    Sort-Object { $_.privateMB } -Descending | Select-Object -First 15)
$c1 = @{}; $procs | ForEach-Object { if ($_.CPU) { $c1[$_.Id] = $_.CPU } }
Start-Sleep -Seconds 5
$cpuNow = @{}
foreach ($p in Get-Process) {
    if ($p.CPU -and $c1.ContainsKey($p.Id)) {
        $pct = 100 * ($p.CPU - $c1[$p.Id]) / 5 / [math]::Max(1, $system.threads)
        if (-not $cpuNow.ContainsKey($p.ProcessName)) { $cpuNow[$p.ProcessName] = 0 }
        $cpuNow[$p.ProcessName] += $pct
    }
}
$topCpu = @($cpuNow.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10 | ForEach-Object { [ordered]@{ name = $_.Key; cpuPctOfMachine = Num $_.Value } })
$processes = [ordered]@{ count = $procs.Count; topByPrivateMemory = $topMemory; topByCpuLast5s = $topCpu }

# ---------------- disk ----------------
function DirSizeGB($path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    Num (((Get-ChildItem -LiteralPath $path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1GB) 2
}
$winOld = Get-Item -LiteralPath 'C:\Windows.old' -Force
$bt     = Get-Item -LiteralPath 'C:\$WINDOWS.~BT' -Force
# The current user's own Recycle Bin folder on each fixed drive is readable without admin.
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$recycleGB = [ordered]@{}
foreach ($v in Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }) {
    $p = "$($v.DriveLetter):\`$Recycle.Bin\$sid"
    if (Test-Path -LiteralPath $p) { $recycleGB["$($v.DriveLetter):"] = Num (((Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1GB) 2 }
}
$disk = [ordered]@{
    volumes  = @(Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.Size -gt 0 } | Sort-Object DriveLetter | ForEach-Object {
                 [ordered]@{ drive = "$($_.DriveLetter):"; fileSystem = $_.FileSystem; sizeGB = Num ($_.Size / 1GB); freeGB = Num ($_.SizeRemaining / 1GB)
                     freePct = Num (100 * $_.SizeRemaining / $_.Size); health = "$($_.HealthStatus)" } })
    physical = @(Get-PhysicalDisk | ForEach-Object { [ordered]@{ name = $_.FriendlyName; mediaType = "$($_.MediaType)"; busType = "$($_.BusType)"; sizeGB = Num ($_.Size / 1GB); health = "$($_.HealthStatus)"; status = "$($_.OperationalStatus)" } })
    windowsOld          = if ($winOld) { [ordered]@{ present = $true; ageDays = Num (((Get-Date) - $winOld.CreationTime).TotalDays) } } else { [ordered]@{ present = $false } }
    windowsBtStaging    = if ($bt) { [ordered]@{ present = $true; ageDays = Num (((Get-Date) - $bt.CreationTime).TotalDays) } } else { [ordered]@{ present = $false } }
    updateDownloadCacheGB = DirSizeGB 'C:\Windows\SoftwareDistribution\Download'
    userTempGB          = DirSizeGB $env:TEMP
    recycleBinGB        = $recycleGB
}
try {
    $disk.reliability = @(Get-PhysicalDisk | ForEach-Object { $d = $_; $r = $d | Get-StorageReliabilityCounter -ErrorAction Stop
        [ordered]@{ name = $d.FriendlyName; wearPct = $r.Wear; temperatureC = $r.Temperature; powerOnHours = $r.PowerOnHours; readErrorsUncorrected = $r.ReadErrorsUncorrected; writeErrorsUncorrected = $r.WriteErrorsUncorrected } })
} catch { $notChecked.Add('SSD wear/temperature (needs admin)') }

# ---------------- stability ----------------
$since30 = (Get-Date).AddDays(-30)
$bugchecks = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1001; StartTime = $since30 } | Where-Object { $_.ProviderName -match 'WER-SystemErrorReporting' } | ForEach-Object {
        $m = $_.Message
        [ordered]@{ time = Dt $_.TimeCreated; code = ([regex]::Match($m, '0x[0-9a-fA-F]{8}')).Value
            params = @([regex]::Matches($m, '0x[0-9a-fA-F]{16}') | ForEach-Object { $_.Value })
            dumpFile = ([regex]::Match($m, '[A-Za-z]:\\[^\s]+\.dmp')).Value } })
$unclean = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 41; StartTime = $since30 } | Where-Object { $_.ProviderName -match 'Kernel-Power' } | ForEach-Object {
        $d = @{}; ([xml]$_.ToXml()).Event.EventData.Data | ForEach-Object { $d[$_.Name] = $_.'#text' }
        [ordered]@{ time = Dt $_.TimeCreated; bugcheckCode = $d['BugcheckCode']; bugcheckParam1 = $d['BugcheckParameter1']; powerButtonPressed = ($d['PowerButtonTimestamp'] -and $d['PowerButtonTimestamp'] -ne '0'); sleepInProgress = $d['SleepInProgress'] } })
$minidumps = $null
try { $minidumps = @(Get-ChildItem 'C:\Windows\Minidump' -Filter *.dmp -ErrorAction Stop | Sort-Object LastWriteTime -Descending | Select-Object -First 10 | ForEach-Object { [ordered]@{ file = $_.Name; time = Dt $_.LastWriteTime; sizeKB = Num ($_.Length / 1KB) 0 } }) }
catch { $notChecked.Add('Minidump folder listing (needs admin; dump paths are taken from crash events instead)') }
$stability = [ordered]@{
    bugchecks30d          = $bugchecks
    uncleanShutdowns30d   = $unclean
    unexpectedShutdowns30d = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 6008; StartTime = $since30 }).Count
    minidumps             = $minidumps
    whea30d               = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $since30 }).Count
}

# ---------------- updates & errors ----------------
$pfro = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager').PendingFileRenameOperations
$wuFail = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WindowsUpdateClient'; Id = 20; StartTime = (Get-Date).AddDays(-14) })
$wuOk = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WindowsUpdateClient'; Id = 19 } -MaxEvents 1
$updates = [ordered]@{
    rebootPendingCBS        = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    rebootRequiredWU        = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    pendingFileRenames      = @($pfro | Where-Object { $_ -and $_.Trim() }).Count
    failures14d             = $wuFail.Count
    failureSamples          = @($wuFail | Group-Object { ([regex]::Match($_.Message, '0x[0-9a-fA-F]{8}')).Value + ' ' + ([regex]::Match($_.Message, ':\s*([^:]+)\.?$')).Groups[1].Value } |
                                Select-Object -First 6 | ForEach-Object { [ordered]@{ count = $_.Count; sample = Short $_.Group[0].Message 150 } })
    lastSuccessfulInstall   = if ($wuOk) { [ordered]@{ time = Dt $wuOk.TimeCreated; what = Short $wuOk.Message 140 } } else { $null }
}
$serviceFailuresThisBoot = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Service Control Manager'; Id = 7000, 7001, 7009, 7011, 7023, 7026, 7031, 7034; StartTime = $boot } |
    ForEach-Object { [ordered]@{ id = $_.Id; message = Short $_.Message 170 } })
$systemErrors7d = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1, 2; StartTime = (Get-Date).AddDays(-7) } |
    Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 15 |
    ForEach-Object { [ordered]@{ count = $_.Count; source = $_.Name; sample = Short $_.Group[0].Message 150 } })

# ---------------- security ----------------
$av = @()
try { $av = @(Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop | ForEach-Object {
            $st = [int]$_.productState
            [ordered]@{ name = $_.displayName; productStateHex = ('0x{0:X6}' -f $st); realTimeOn = (($st -band 0x1000) -ne 0); upToDate = (($st -band 0x10) -eq 0) } }) }
catch { $notChecked.Add('Registered antivirus products (SecurityCenter2)') }
$def = $null
try { $m = Get-MpComputerStatus -ErrorAction Stop
    $def = [ordered]@{ runningMode = "$($m.AMRunningMode)"; realTimeProtection = $m.RealTimeProtectionEnabled; signatureAgeDays = $m.AntivirusSignatureAge; quickScanAgeDays = $m.QuickScanAge } }
catch { $notChecked.Add('Microsoft Defender status') }
# File-system filter drivers in the anti-virus load-order group, from any vendor (language-neutral, no admin needed)
$drvState = @{}; Get-CimInstance Win32_SystemDriver | ForEach-Object { $drvState[$_.Name] = $_.State }
$avFilters = @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath
        if ($p.Group -match 'FSFilter Anti-Virus|FSFilter Activity Monitor' -and $p.Start -le 2) {
            [ordered]@{ driver = $_.PSChildName; group = $p.Group; start = $p.Start; state = $drvState[$_.PSChildName]; image = Short $p.ImagePath 90 } } })
$security = [ordered]@{
    registeredAntivirus = $av
    defender            = $def
    avFilterDrivers     = $avFilters
    vbs                 = (Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard).VirtualizationBasedSecurityStatus
}

# ---------------- virtualization ----------------
$virtualization = [ordered]@{
    hypervisorPresent = $cs.HypervisorPresent
    features          = @(Get-CimInstance Win32_OptionalFeature | Where-Object { $_.Name -match '^(Microsoft-Hyper-V-All|VirtualMachinePlatform|HypervisorPlatform|Microsoft-Windows-Subsystem-Linux|Containers-DisposableClientVM)$' } |
                          ForEach-Object { [ordered]@{ name = $_.Name; enabled = ($_.InstallState -eq 1) } })
    thirdPartyHypervisorDrivers = @(Get-CimInstance Win32_SystemDriver | Where-Object { $_.Name -match '^(VBox\w*|IntelHaxm|vmx86|vmci|vmusb|hcmon|AEHD|gvm)$' } |
                          ForEach-Object { [ordered]@{ name = $_.Name; state = $_.State; startMode = $_.StartMode } })
}
# Who owns vmmem? It is shared by WSL2, Docker Desktop, Windows Sandbox and app-specific VMs, so
# never assume it is WSL. Collect the candidates and let the report say which one fits.
$vmmem = @(Get-Process -Name 'vmmem*' -ErrorAction SilentlyContinue)
$wslRunning = @()
try { $wslRunning = @(((& wsl.exe -l --running -q) 2>$null) -replace "`0", '' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) } catch {}
$vmServices = @(Get-CimInstance Win32_Service | Where-Object { $_.State -eq 'Running' -and ($_.Name -match '^(CoworkVMService|vmcompute|com\.docker\.service|WSLService|LxssManager)$' -or $_.DisplayName -match 'Virtual Machine|Sandbox') } |
                ForEach-Object { [ordered]@{ name = $_.Name; displayName = $_.DisplayName } })
$dockerUi = [bool](Get-Process -Name 'Docker Desktop', 'com.docker.backend' -ErrorAction SilentlyContinue)
$sandbox  = [bool](Get-Process -Name 'WindowsSandbox*' -ErrorAction SilentlyContinue)
$appVm    = @($vmServices | Where-Object { $_.name -notmatch '^(vmcompute|WSLService|LxssManager|com\.docker\.service)$' } | ForEach-Object { $_.displayName })
$owner = if (-not $vmmem) { 'no VM running' }
         elseif ($wslRunning | Where-Object { $_ -notmatch '^docker-desktop' }) { "WSL distro(s): $(($wslRunning | Where-Object { $_ -notmatch '^docker-desktop' }) -join ', ')" }
         elseif ($dockerUi -or ($wslRunning -match '^docker-desktop')) { 'Docker Desktop' }
         elseif ($sandbox) { 'Windows Sandbox' }
         elseif ($appVm) { "App VM service: $($appVm -join ', ')" }
         else { 'unknown (no WSL distro, Docker or Sandbox running)' }
$virtualization.vmmem = [ordered]@{
    running = [bool]$vmmem
    workingSetMB = Num ((($vmmem | Measure-Object WorkingSet64 -Sum).Sum) / 1MB) 0
    wslRunningDistros = $wslRunning
    dockerDesktopRunning = $dockerUi
    windowsSandboxRunning = $sandbox
    vmRelatedServicesRunning = $vmServices
    likelyOwner = $owner
}

# ---------------- software: startup + OEM agents ----------------
$approved = @{}
foreach ($k in 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
               'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder') {
    if (Test-Path $k) { (Get-ItemProperty $k).PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { $approved[$_.Name] = ($_.Value[0] -eq 2 -or $_.Value[0] -eq 6) } }
}
$startup = @()
foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run') {
    if (Test-Path $k) { (Get-ItemProperty $k).PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
            $startup += [ordered]@{ name = $_.Name; enabled = (-not $approved.ContainsKey($_.Name) -or $approved[$_.Name]); command = Short ($_.Value -replace [regex]::Escape($env:USERPROFILE), '%USERPROFILE%') 110 } } }
}
foreach ($f in "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup") {
    Get-ChildItem $f -File | Where-Object { $_.Name -ne 'desktop.ini' } | ForEach-Object { $startup += [ordered]@{ name = $_.Name; enabled = (-not $approved.ContainsKey($_.Name) -or $approved[$_.Name]); command = 'Startup folder' } }
}
$oemPattern = 'SupportAssist|Dell|TechHub|ServiceShell|FusionService|SmartByte|Rivet|Killer|RAPS|HP\w*(Analytics|Support|Touchpoint|Sure)|HPCommRecovery|Lenovo|Vantage|ImController|ArmouryCrate|MyASUS|AsusSoftware|\bROGLive|AcerCare|Acer\w*Service|McAfee|^mc(shield|apexe|uicnt)|Norton|WildTangent'
$oemProcs = @($procs | Where-Object { $_.ProcessName -match $oemPattern -and $_.ProcessName -notmatch '^(svchost|explorer)$' })
$software = [ordered]@{
    startupEntries = $startup
    oemAgents = [ordered]@{
        processCount = $oemProcs.Count
        privateMB    = Num ((($oemProcs | Measure-Object PrivateMemorySize64 -Sum).Sum) / 1MB) 0
        byName       = @($oemProcs | Group-Object ProcessName | Sort-Object { ($_.Group | Measure-Object PrivateMemorySize64 -Sum).Sum } -Descending |
                         ForEach-Object { [ordered]@{ name = $_.Name; privateMB = Num ((($_.Group | Measure-Object PrivateMemorySize64 -Sum).Sum) / 1MB) 0 } })
        autoServices = @(Get-CimInstance Win32_Service | Where-Object { $_.StartMode -eq 'Auto' -and ($_.Name -match $oemPattern -or $_.DisplayName -match $oemPattern) } |
                         ForEach-Object { [ordered]@{ name = $_.Name; displayName = $_.DisplayName; state = $_.State } })
    }
}

# ---------------- drivers / devices ----------------
$drivers = [ordered]@{
    problemDevices = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 } | ForEach-Object { [ordered]@{ name = $_.Name; errorCode = $_.ConfigManagerErrorCode } })
    gpus           = @(Get-CimInstance Win32_VideoController | ForEach-Object { [ordered]@{ name = $_.Name; driverVersion = $_.DriverVersion; driverDate = Dt $_.DriverDate 'yyyy-MM-dd' } })
    networkAdapters = @(Get-NetAdapter | ForEach-Object { [ordered]@{ name = $_.Name; description = $_.InterfaceDescription; status = "$($_.Status)"; linkSpeed = $_.LinkSpeed
                         driverVersion = $_.DriverVersion; driverDate = $_.DriverDate; driverProvider = $_.DriverProvider } })
}

# ---------------- network (basic; see network-test.ps1 for performance) ----------------
$route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1
$net = [ordered]@{ connected = [bool]$route }
if ($route) {
    $a = Get-NetAdapter -InterfaceIndex $route.ifIndex
    $net.adapter     = $a.Name
    $net.description = $a.InterfaceDescription
    $net.linkSpeed   = $a.LinkSpeed
    $net.gateway     = $route.NextHop
    $net.dnsServers  = @((Get-DnsClientServerAddress -InterfaceIndex $route.ifIndex -AddressFamily IPv4).ServerAddresses)
    $net.connectionHint = if ($route.NextHop -like '172.20.10.*') { 'iPhone Personal Hotspot subnet' } elseif ($route.NextHop -like '192.168.43.*') { 'Android hotspot subnet' } elseif ($a.InterfaceDescription -match 'Remote NDIS|RNDIS') { 'USB tethering / USB modem (RNDIS)' } else { $null }
    $st = Get-NetAdapterStatistics -Name $a.Name
    $net.adapterErrors = [ordered]@{ rxErrors = $st.ReceivedPacketErrors; rxDiscards = $st.ReceivedDiscardedPackets; txErrors = $st.OutboundPacketErrors }
    $wl = netsh wlan show interfaces 2>$null | Out-String
    if ($a.InterfaceDescription -match 'Wi-?Fi|Wireless|802\.11|WLAN' -and $wl) {
        $w = [ordered]@{}
        foreach ($f in 'Band', 'Channel', 'Radio type', 'Receive rate \(Mbps\)', 'Transmit rate \(Mbps\)', 'Signal') {
            $mt = [regex]::Match($wl, "(?m)^\s*$f\s*:\s*(.+)$"); if ($mt.Success) { $w[($f -replace ' \\\(Mbps\\\)', '' -replace ' ', '')] = $mt.Groups[1].Value.Trim() }
        }
        $net.wifi = $w
    }
    $net.wifiDisconnects7d = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-WLAN-AutoConfig/Operational'; Id = 8003; StartTime = (Get-Date).AddDays(-7) }).Count
    $net.ndisResets7d = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-NDIS'; StartTime = (Get-Date).AddDays(-7) }).Count
    # Is Windows treating this connection as metered? Matters on capped mobile data.
    try {
        $null = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]
        $prof = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile()
        if ($prof) { $cost = $prof.GetConnectionCost(); $net.connectionCost = [ordered]@{ costType = "$($cost.NetworkCostType)"; roaming = $cost.Roaming; approachingDataLimit = $cost.ApproachingDataLimit; overDataLimit = $cost.OverDataLimit } }
    } catch { $notChecked.Add('Metered-connection setting (WinRT query failed)') }
}

# ---------------- generic evidence for common problems ----------------
# Per-process disk I/O ("100% disk"). CIM formatted counters need a warm-up read; the second read is real.
$null = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process
Start-Sleep -Seconds 2
$topDiskIO = @(Get-CimInstance Win32_PerfFormattedData_PerfProc_Process | Where-Object { $_.Name -notmatch '^(_Total|Idle)$' -and $_.IODataBytesPersec -gt 0 } |
    Sort-Object IODataBytesPersec -Descending | Select-Object -First 8 |
    ForEach-Object { [ordered]@{ name = ($_.Name -replace '#\d+$', ''); readKBps = Num ($_.IOReadBytesPersec / 1KB) 0; writeKBps = Num ($_.IOWriteBytesPersec / 1KB) 0 } })
$processes.topByDiskIO = $topDiskIO
$processes.topByHandles = @(Get-Process | Sort-Object HandleCount -Descending | Select-Object -First 5 | ForEach-Object { [ordered]@{ name = $_.ProcessName; handles = $_.HandleCount; privateMB = Num ($_.PrivateMemorySize64 / 1MB) 0 } })

# Unsigned programs running from user-writable folders: a common malware/adware signal (not proof).
$writable = @($env:TEMP, $env:APPDATA, (Join-Path $env:USERPROFILE 'Downloads'), 'C:\Users\Public') | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') + '\' }
$suspect = @()
foreach ($p in (Get-Process | Where-Object { $_.Path } | Sort-Object Path -Unique)) {
    $inWritable = $false; foreach ($w in $writable) { if ($p.Path.StartsWith($w, [StringComparison]::OrdinalIgnoreCase)) { $inWritable = $true; break } }
    if (-not $inWritable) { continue }
    $sig = Get-AuthenticodeSignature -LiteralPath $p.Path
    if ("$($sig.Status)" -ne 'Valid') {
        $suspect += [ordered]@{ name = $p.ProcessName; path = ($p.Path -replace [regex]::Escape($env:USERPROFILE), '%USERPROFILE%'); signature = "$($sig.Status)"; company = $p.Company }
    }
}
$security.unsignedProcessesInUserFolders = $suspect
try { $det = @(Get-MpThreatDetection -ErrorAction Stop | Where-Object { $_.InitialDetectionTime -gt (Get-Date).AddDays(-30) })
      $security.defenderDetections30d = @($det | Select-Object -First 10 | ForEach-Object { [ordered]@{ time = Dt $_.InitialDetectionTime; threatId = $_.ThreatID; actionSuccess = $_.ActionSuccess } }) }
catch { $notChecked.Add('Defender detection history (needs admin)') }

# Installed "PC optimizer"/cleaner tools and third-party antivirus (from installed programs).
$installed = @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' |
    Where-Object { $_.DisplayName } | Select-Object DisplayName, DisplayVersion -Unique)
$software.optimizerTools = @($installed | Where-Object { $_.DisplayName -match 'CCleaner|Advanced SystemCare|IObit|Driver Booster|Driver Easy|DriverPack|Avast Cleanup|AVG TuneUp|Wise Care|Glary|Razer Cortex|PC Optimizer|Reimage|Restoro|Fortect|Outbyte|Auslogics|WinOptimizer|Norton Utilities|Smart PC|Speedup|Registry (Cleaner|Mechanic)' } | ForEach-Object { "$($_.DisplayName) $($_.DisplayVersion)".Trim() })
$software.thirdPartyAntivirus = @($installed | Where-Object { $_.DisplayName -match '^(Avast|AVG |Avira|Bitdefender|ESET|Kaspersky|McAfee|Norton|Malwarebytes|Sophos|Trend Micro|Webroot|Panda|360 Total|Quick Heal|K7|Comodo|Total ?AV|TotalAV|ZoneAlarm|F-Secure|G DATA)' } | ForEach-Object { "$($_.DisplayName) $($_.DisplayVersion)".Trim() })

# App crashes and hangs (Application log), grouped by program.
$appEvents = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error', 'Application Hang'; StartTime = (Get-Date).AddDays(-14) })
$stability.appCrashesAndHangs14d = @($appEvents | ForEach-Object {
        $d = @(([xml]$_.ToXml()).Event.EventData.Data); [pscustomobject]@{ app = "$($d[0].'#text')"; kind = $(if ($_.ProviderName -eq 'Application Hang') { 'hang' } else { 'crash' }) } } |
    Group-Object app, kind | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { [ordered]@{ count = $_.Count; app = $_.Group[0].app; kind = $_.Group[0].kind } })

# Which kind of drive Windows runs from (HDD vs SSD vs eMMC is often the whole story on older/budget machines).
try {
    $part = Get-Partition -DriveLetter ($env:SystemDrive.TrimEnd(':')) -ErrorAction Stop
    $pd = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq "$($part.DiskNumber)" } | Select-Object -First 1
    $disk.systemDrive = [ordered]@{ drive = $env:SystemDrive; mediaType = "$($pd.MediaType)"; busType = "$($pd.BusType)"; model = $pd.FriendlyName; spindleSpeed = $pd.SpindleSpeed }
} catch { $notChecked.Add('System drive type (partition query failed)') }

# Boot and sleep configuration.
$pwr = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'
$power.fastStartupEnabled = ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power').HiberbootEnabled -eq 1)
$power.hibernateEnabled = if ($null -ne $pwr.HibernateEnabled) { $pwr.HibernateEnabled -eq 1 } else { $null }

# Display and gaming-related settings (relevant to stutter/FPS complaints).
$gc = Get-ItemProperty 'HKCU:\System\GameConfigStore'
$gd = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'
$gb = Get-ItemProperty 'HKCU:\Software\Microsoft\GameBar'
$vf = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
$gfx = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
$display = [ordered]@{
    screens = @(Get-CimInstance Win32_VideoController | Where-Object { $_.CurrentHorizontalResolution } | ForEach-Object { [ordered]@{ gpu = $_.Name; resolution = "$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)"; refreshHz = $_.CurrentRefreshRate } })
    backgroundRecording = [ordered]@{ gameDVR = ($gc.GameDVR_Enabled -eq 1); appCapture = ($gd.AppCaptureEnabled -eq 1) }
    gameModeAuto = if ($null -ne $gb.AutoGameModeEnabled) { $gb.AutoGameModeEnabled -eq 1 } else { 'default (on)' }
    hardwareGpuScheduling = switch ($gfx.HwSchMode) { 2 { 'on' } 1 { 'off' } default { 'default' } }
    visualEffects = switch ($vf.VisualFXSetting) { 0 { 'let Windows choose' } 1 { 'best appearance' } 2 { 'best performance' } 3 { 'custom' } default { 'default' } }
}

# ---------------- output ----------------
if (-not $isAdmin) { $notChecked.Add('Running without admin by design: boot-time breakdown, BitLocker status, memory-manager settings and minidump contents are not read') }
$result = [ordered]@{
    schema = 'windows-perf-diagnosis/snapshot@2'
    system = $system; power = $power; battery = $battery; memory = $memory; live = $live; processes = $processes; disk = $disk
    stability = $stability; updates = $updates; serviceFailuresThisBoot = $serviceFailuresThisBoot; systemErrors7d = $systemErrors7d
    security = $security; virtualization = $virtualization; software = $software; drivers = $drivers; network = $net
    display = $display
    notChecked = @($notChecked)
}
$json = $result | ConvertTo-Json -Depth 8
if ($OutFile) {
    $dir = Split-Path -Parent $OutFile
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($OutFile, $json, (New-Object Text.UTF8Encoding($false)))
    "Snapshot written to $OutFile"
} else { $json }
