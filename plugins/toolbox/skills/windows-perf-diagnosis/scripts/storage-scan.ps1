<#
.SYNOPSIS
  Read-only folder-size scan. Uses robocopy in list-only mode (/L), which copies and changes
  nothing but is far faster than Get-ChildItem on large trees.
.PARAMETER Roots
  Folders whose immediate subfolders are measured. Default: each fixed drive root, the user
  profile, AppData\Local, AppData\Roaming, Program Files (both) and ProgramData - large SDKs and
  editors (Unity, Android, Anaconda) usually live in the last three.
.PARAMETER Top
  Subfolders reported per root (default 12).
.PARAMETER OutFile
  Path for the JSON output. Prints to stdout if omitted.
#>
param([string[]]$Roots, [int]$Top = 12, [string]$OutFile)
$ErrorActionPreference = 'SilentlyContinue'

function SizeGB([string]$path) {
    $o = robocopy $path "$env:TEMP\__wpd_nul__" /L /S /NJH /NFL /NDL /BYTES /R:0 /W:0 /XJ /MT:8 2>$null
    # The summary's third row is bytes. Its label is localized, so fall back to position.
    $line = $o | Where-Object { $_ -match '^\s*Bytes\s*:' } | Select-Object -First 1
    if (-not $line) { $rows = @($o | Where-Object { $_ -match ':\s+\d+' }); if ($rows.Count -ge 3) { $line = $rows[$rows.Count - 2] } }
    if (-not $line) { return $null }
    $n = ($line -split '\s+' | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1)
    if ($n) { [math]::Round([double]$n / 1GB, 2) } else { $null }
}

if (-not $Roots) {
    $Roots = @(Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | Sort-Object DriveLetter | ForEach-Object { "$($_.DriveLetter):\" }) +
             @($env:USERPROFILE, $env:LOCALAPPDATA, $env:APPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData)
}
$user = $env:USERNAME
$results = @()
foreach ($r in $Roots) {
    if (-not (Test-Path -LiteralPath $r)) { continue }
    $sub = @(Get-ChildItem -LiteralPath $r -Directory -Force | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } | ForEach-Object {
            [ordered]@{ folder = $_.Name; gb = SizeGB $_.FullName; lastWrite = $_.LastWriteTime.ToString('yyyy-MM-dd') } } |
        Sort-Object { [double]$_.gb } -Descending | Select-Object -First $Top)
    $results += [ordered]@{ root = ($r -replace [regex]::Escape($user), '%USERNAME%'); top = $sub }
}

# Well-known regenerable caches. Listed for the report; nothing is removed.
$known = [ordered]@{
    'pip cache'               = "$env:LOCALAPPDATA\pip\cache"
    'npm cache'               = "$env:LOCALAPPDATA\npm-cache"
    'yarn cache'              = "$env:LOCALAPPDATA\Yarn\Cache"
    'Hugging Face models'     = "$env:USERPROFILE\.cache\huggingface"
    'other .cache'            = "$env:USERPROFILE\.cache"
    'Squirrel installer temp' = "$env:LOCALAPPDATA\SquirrelTemp"
    'User temp'               = $env:TEMP
    'Windows temp'            = 'C:\Windows\Temp'
    'Docker Desktop data'     = "$env:LOCALAPPDATA\Docker"
    'Chrome cache'            = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
    'Edge cache'              = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
    'Downloads'               = "$env:USERPROFILE\Downloads"
}
$caches = foreach ($k in $known.Keys) { $p = $known[$k]; if (Test-Path -LiteralPath $p) { [ordered]@{ name = $k; path = ($p -replace [regex]::Escape($user), '%USERNAME%'); gb = SizeGB $p } } }

# Every file over 1 GB on each fixed drive (robocopy /MIN filter, list-only): finds forgotten VM disks, ISOs, Docker images.
$big = @()
foreach ($v in Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }) {
    $o = robocopy "$($v.DriveLetter):\" "$env:TEMP\__wpd_nul__" /L /S /MIN:1073741824 /NJH /NJS /NDL /NC /BYTES /FP /XJ /R:0 /W:0 /XF pagefile.sys hiberfil.sys swapfile.sys 2>$null
    foreach ($l in $o) { if ($l -match '^\s*(\d+)\s+(\S.*)$') { $big += [pscustomobject]@{ bytes = [double]$Matches[1]; path = $Matches[2].Trim() } } }
}
$largeFiles = @($big | Sort-Object bytes -Descending | Select-Object -First 20 | ForEach-Object {
        $f = Get-Item -LiteralPath $_.path -Force
        [ordered]@{ path = ($_.path -replace [regex]::Escape($user), '%USERNAME%'); gb = [math]::Round($_.bytes / 1GB, 2); lastWrite = if ($f) { $f.LastWriteTime.ToString('yyyy-MM-dd') } else { $null } } })

$res = [ordered]@{
    schema = 'windows-perf-diagnosis/storage@1'; scannedAt = (Get-Date).ToString('s')
    note = 'Sizes from robocopy list-only. C:\Windows is overstated because WinSxS uses hard links.'
    roots = $results; knownCaches = @($caches); filesOver1GB = $largeFiles
}
$json = $res | ConvertTo-Json -Depth 6
if ($OutFile) { [IO.File]::WriteAllText($OutFile, $json, (New-Object Text.UTF8Encoding($false))); "Storage scan written to $OutFile" } else { $json }
