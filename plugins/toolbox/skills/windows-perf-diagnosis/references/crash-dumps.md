# Naming the driver behind a blue screen (optional, needs consent)

The snapshot already gives each crash's bugcheck code, parameters and dump path from the
event log — no admin needed. That is often enough to narrow it down (see the bugcheck table
in `interpretation.md`). To name the exact driver you need the dump itself, which means:

1. **Installing Microsoft's debugger** — ask first; it's a ~100 MB download:
   `winget install --id Microsoft.WinDbg -e --source winget`
2. **Admin once**, to copy the dump out of `C:\Windows\Minidump` (only admins can read it).
3. **A few MB of symbol downloads** from Microsoft on first use.

Only do this if the person agrees. Otherwise report the code, its usual causes, and
"exact driver not identified (needs dump analysis)".

## Steps

```powershell
# cdb.exe ships inside the WinDbg package
$pkg = Get-AppxPackage -Name 'Microsoft.WinDbg*'
$cdb = Join-Path $pkg.InstallLocation 'amd64\cdb.exe'      # arm64\cdb.exe on ARM

# Keep the working folder SHORT: symbol paths beyond 260 characters fail silently and you get
# "WRONG_SYMBOLS" with nothing downloaded.
$work = "$env:LOCALAPPDATA\Temp\sym"; New-Item -ItemType Directory -Force $work | Out-Null
# (copy the .dmp into $work from an elevated prompt, after the person approves the UAC prompt)

& $cdb -z "$work\crash.dmp" -logo "$work\analyze.txt" -y "srv*$work*https://msdl.microsoft.com/download/symbols" `
  -c "!analyze -v; .echo ===DEVSTACK===; !devstack @`$bug_param2; q"
Select-String "$work\analyze.txt" -Pattern 'BUGCHECK_CODE|IMAGE_NAME|MODULE_NAME|FAILURE_BUCKET_ID|\\Driver\\'
```

Read `IMAGE_NAME`, `FAILURE_BUCKET_ID` and the device stack. For 0x9F subcode 3 the device stack
shows which driver held the power request.

**Afterwards, delete the dump copy** (it contains a snapshot of memory) and tell the person the
symbol cache folder can be removed too. WinDbg can stay installed for future crashes, or be
uninstalled with `winget uninstall Microsoft.WinDbg`.

## Common modules

| Module | Usually |
|---|---|
| `usbccgp.sys` + `usbrndis6` / `usb80236` | USB modem or USB tethering (phone, 4G dongle) |
| `Netwtw*.sys`, `athw*.sys`, `Qcamain*.sys`, `rtwlane*.sys` | Wi-Fi driver (Intel, Qualcomm Atheros, Realtek) |
| `ndis.sys`, `tcpip.sys` with a third-party filter in the stack | VPN or AV network filter |
| `nvlddmkm.sys` / `igdkmd64.sys` / `amdkmdag.sys` | NVIDIA / Intel / AMD graphics driver |
| `storport.sys`, `stornvme.sys`, `iaStorAC.sys` | Storage driver or SSD firmware |
| Vendor AV names (e.g. `eamonm`, `ehdrv`, `klif`, `aswSP`) | Antivirus filter driver |
| `ntoskrnl.exe` alone | Not informative by itself; look at the stack, or suspect hardware |
