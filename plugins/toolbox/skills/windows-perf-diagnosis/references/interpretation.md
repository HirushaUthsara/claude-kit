# Interpreting the measurements

Contents: 1. Thresholds · 2. Finding the bottleneck · 3. Culprit catalogue · 4. Bugcheck codes · 5. Network patterns

Thresholds are rules of thumb for a typical laptop/desktop, not laws. Always read
metrics together — one number alone rarely proves anything.

## 1. Thresholds

### Memory
| Metric | Healthy | Tight | Problem |
|---|---|---|---|
| Available RAM (8 GB machine) | > 1.5 GB | 0.5–1.5 GB | < 500 MB sustained |
| Commit % of limit | < 70% | 70–85% | > 85% |
| Pages/sec (median of samples) | < 200 | 200–2,000 | > 2,000 sustained; > 5,000 = thrashing |

| Kernel nonpaged pool | < 400 MB | 400–800 MB | > 800 MB (a driver is holding memory; owner needs admin `poolmon`) |
| Memory Compression process | — | > 1 GB = Windows is squeezing RAM hard | |

Pages/sec also counts normal file reads (app launches), so single spikes are fine. Thrashing
is **sustained** paging *plus* low available RAM *plus* high commit. If `commitLimitGB` is far
above physical RAM + the original pagefile, Windows has been auto-growing the pagefile because
it ran out — that also explains "disappearing" free space on C:.

### CPU
| Metric | Meaning |
|---|---|
| Run queue (`runQueue`) | Threads waiting for a CPU. Sustained > 2 × core count = CPU-bound. 0–1 = CPU is not the bottleneck. |
| CPU % | Sustained > 85% *with* a run queue = CPU-bound. High % alone (e.g. during your own scan) is not. |
| `cpuPerfPct` | Speed vs the nominal base. > 100% = turbo. Under load, < ~70% means clocks are being held down. |
| Load test `minPerfLimitPct` < 100 or throttle events > 0 | Thermal/power throttling. |
| Load test: low MHz, no throttle events, limit 100%, power mode "Best power efficiency" | Clocks capped by power policy, not heat. Fix: Settings → System → Power & battery → Power mode. |

WMI's `MaxClockSpeed` / "Processor Frequency" is the nominal base, not live speed. Use
`cpuPerfPct` × base for real MHz.

### Disk
| Metric | NVMe/SATA SSD | HDD |
|---|---|---|
| Avg read/write latency | < 5 ms good, > 20 ms bad | < 15 ms ok, > 30 ms bad |
| % idle | < 20% sustained with high latency = disk-bound | |
| Free space | < 10% low, < 5% critical (updates fail, pagefile can't grow) | |

Health "Warning"/"Unhealthy", uncorrected read/write errors, or wear > 80% → back up first,
then replace the drive. This outranks every other finding.

### Battery
`battery.healthPct` = full-charge ÷ design capacity. > 80% fine; 60–80% worn (shorter runtime,
not a performance cause); < 60% plan a replacement. A worn battery can make Windows lower
performance on battery power — compare behaviour on AC vs battery before blaming the CPU.

### Uptime and timing
- Uptime < 15 min: boot settling inflates CPU and paging. Resample or say so.
- Uptime > 7 days, or a pending reboot: reboot before drawing deeper conclusions.

## 2. Finding the bottleneck

| Evidence pattern | Bottleneck |
|---|---|
| Low available RAM, high commit, sustained paging, CPU mostly idle, run queue 0 | **Memory** |
| High CPU %, sustained run queue, little paging | **CPU** (find which process) |
| Disk latency high, % idle low, disk queue high | **Disk** (check health, free space, AV scanning) |
| All of the above fine, but stutters/freezes | Drivers, crashes, AV filters, thermal — check stability and events |
| Gateway ping fine, internet ping/loss bad | **Upstream** (ISP / mobile network), not the PC |
| Gateway ping bad or adapter errors | **Local link** (Wi-Fi signal/channel, cable, driver) |

Say which bottleneck the evidence points to *and* which it rules out — "the CPU is not the
cause: run queue 0 in every sample" is as useful as the positive finding.

## 3. Culprit catalogue

Each entry: signature in the data → what it means → recommended fix (risk).

**RAM ceiling.** 8 GB or less with browsers + Electron apps (Teams, Slack, Notion, VS Code,
Claude, Discord) + WSL/Docker (`vmmem`) → memory-bound. Fix: add RAM (money). Check the
*manufacturer's* spec for slot count — `smbiosReportedSlots` is often wrong (reported 8 on a
2-slot laptop). One stick in a 2-slot machine = single-channel; adding a matched stick also
doubles bandwidth (helps integrated graphics). Mixed speeds all run at the slowest stick's speed.
Mixed sizes (e.g. 8 + 16 GB) run in "flex mode": only the matched part (2 × 8 GB) is
dual-channel — say so if suggesting an unmatched stick.
Interim free fixes: browser memory saver, close/disable heavy startup apps, and whatever
actually owns `vmmem` (below).

**`vmmem` — find the owner before advising.** `vmmem` hosts *any* Hyper-V-based VM: WSL2
distros, Docker Desktop, Windows Sandbox, and app VMs (e.g. the Claude desktop app's
`CoworkVMService`). Use `virtualization.vmmem.likelyOwner`. Only recommend `wsl --shutdown`
or a `.wslconfig` memory cap when a WSL distro or Docker is actually running; for an app VM,
the fix is closing that app's feature when idle.

**Stuck Windows Update loop.** Pending reboot flags true, `pendingFileRenames` high, repeated
failures with `0x80073D02` (package in use) / `0x80240016` (another install in progress), large
update cache or old `$WINDOWS.~BT` → servicing keeps retrying. Fix: reboot first (free, low risk),
then Disk Cleanup → Windows Update Cleanup. Don't clear caches *before* the reboot.

**Broken or duplicate antivirus.** More than one product registered, a non-Microsoft driver in the
`FSFilter Anti-Virus` group loaded while that vendor's service fails at boot (often "cannot verify
the digital signature"), and Defender in `Normal` mode → double scanning of every file operation
with no protection from the broken one. Fix: the vendor's official removal tool. Silent uninstall is
often blocked by design; protected AV services may only uninstall from Safe Mode. Before advising
Safe Mode, have the person confirm they can get their BitLocker recovery key (account.microsoft.com
/devices/recoverykey) — never read or print the key yourself. Defender keeps them protected meanwhile.

**OEM agents.** Dell SupportAssist/TechHub/Digital Delivery, Rivet/Killer SmartByte, HP Support
Assistant/Analytics, Lenovo Vantage/ImController, ASUS Armoury Crate/MyASUS, Acer Care Center,
McAfee/Norton trials. Often 0.5–1.5 GB combined. SmartByte specifically is known for network lag.
Fix: uninstall the optional ones (reversible via the vendor site). Keep the vendor's *driver/BIOS
update* tool until drivers are current — and name it exactly as it appears in installed programs
(e.g. Dell ships both "Dell Update for Windows Universal" and "Dell Command | Update"; tell the
person to keep whichever one is actually installed). Check no power/thermal manager (e.g. Dell Power Manager,
Lenovo energy drivers) is removed by mistake.

**Hypervisor conflicts.** `hypervisorPresent` true (Hyper-V / VBS / WSL2) plus VirtualBox, Intel
HAXM or VMware drivers. HAXM cannot work alongside Hyper-V and fails at every boot; old VirtualBox
network filters can destabilise networking. Fix: remove unused ones; HAXM is discontinued.
Check for orphaned VM disks (`.vdi/.vmdk/.vhdx`) afterwards — they can be tens of GB.

**Power mode stuck on "Best power efficiency".** Shows in `power.modeOnAC`. Caps CPU even on AC.
Fix: Settings → System → Power & battery → Power mode (free, instant, reversible).

**Old Windows installation / staging.** `windowsOld.present` and `windowsBtStaging` — usually
20–50 GB. If `ageDays` < 10 it is the rollback for a recent update: advise waiting. Older: Disk
Cleanup → "Previous Windows installation(s)".

**Pagefile growth.** See memory thresholds. The fix is the memory fix; the space returns when
pressure drops (and after reboot).

**Startup load.** Many `startupEntries` with `enabled: true`, especially updaters, chat apps and
OEM tools. Entries with `enabled: false` are already turned off — don't list them as starting
with Windows. Fix: Task Manager → Startup apps → Disable (reversible). Ask what they actually need —
some entries look like bloat but are essential to them (e.g. a USB modem's helper).

**Background downloads on a capped connection.** `network.connectionCost.costType` is
`Unrestricted` on a phone hotspot or USB modem → Windows Update, Store and app updaters download
freely and eat the data plan. USB modems often appear as "Ethernet", which Windows never marks
metered by default. Fix: Settings → Network & internet → (that connection) → Metered connection On
(free, reversible). Many 4G modems/routers also show signal and monthly usage on their own status
page at the gateway address — suggest the person check it (it may need their login).

**USB modem / dongle noise.** `cdrom` and `disk` errors (event 11) on a USB storage device that is a
modem's virtual CD or card slot → harmless log noise, not a failing disk. Confirm the device name
before telling anyone their drive is failing.

**HDD or eMMC system drive.** `disk.systemDrive.mediaType` = HDD (or busType SD/MMC) → slow
boots, app launches and "100% disk" even when nothing is wrong. Fix: clone to an SSD (money, the
biggest single upgrade for such machines). Until then: fewer startup apps, avoid indexing large
folders, keep free space > 15%.

**Handle leak.** One non-system process with > 10,000 handles (`processes.topByHandles`), often
growing over uptime, usually alongside high kernel pool. Fix: restart that program (free); report
the program to its vendor; update it.

**"PC optimizer" / driver-updater tools.** `software.optimizerTools` non-empty → nags, bundled
installs, aggressive registry "cleaning", wrong drivers. Fix: uninstall (reversible). Windows needs
none of them.

**Unsigned programs in user folders.** `security.unsignedProcessesInUserFolders` → possible malware
or adware. Look up the name and path before alarming anyone; recommend a Microsoft Defender Offline
scan (the person runs it). Never delete files yourself.

**Repeated app crashes/hangs.** `stability.appCrashesAndHangs14d` concentrated on one app → that app
(update, repair, reset its settings, check add-ins), not Windows. Spread across many apps → memory,
disk, AV or driver problem underneath.

**Background recording / visual effects on weak GPUs.** `display.backgroundRecording.appCapture` on
→ Xbox Game Bar records in the background (Settings → Gaming → Captures). Low-end machines also gain
from Settings → System → About → Advanced system settings → Performance → "Adjust for best
performance" (reversible).

**Non-default memory tweaks.** `DisablePagingExecutive = 1` (common "optimizer" setting) keeps
kernel code in RAM — minor cost on low-RAM machines. Low priority.

## 4. Bugcheck (blue screen) codes

`stability.bugchecks30d` gives the code and parameters from the event log without admin.
Kernel-Power 41 with `bugcheckCode` 0 and no power-button press = hang or power loss, *not* a
blue screen (often a shutdown/sleep that never finished).

| Code | Name | Usual causes |
|---|---|---|
| 0x9F | DRIVER_POWER_STATE_FAILURE | A driver didn't finish a sleep/shutdown transition. P1=3: blocked IRP; the dump names the driver. Common: USB network/modem (usbccgp/usbrndis6), Wi-Fi, AV/filter drivers. |
| 0x14F | PDC_WATCHDOG_TIMEOUT | Same family as 0x9F, Modern Standby. |
| 0x133 | DPC_WATCHDOG_VIOLATION | Storage or network driver, SSD firmware. |
| 0xD1 / 0xA | DRIVER_IRQL_NOT_LESS_OR_EQUAL | Usually network/Wi-Fi or VPN drivers. |
| 0x7E / 0x1E / 0x3B | Unhandled exception | Driver bug; dump names it. |
| 0x50 / 0x1A | Page fault / memory management | Driver or faulty RAM → suggest Windows Memory Diagnostic. |
| 0x124 | WHEA_UNCORRECTABLE_ERROR | Hardware: overheating, overclock/undervolt, failing CPU/RAM. Check `whea30d`. |
| 0x116 / 0x117 | VIDEO_TDR | GPU driver or GPU hardware. |
| 0xEF | CRITICAL_PROCESS_DIED | System file or disk corruption → `sfc /scannow`, check disk health. |

One code repeated across crashes points strongly at one cause; mixed codes point at hardware
(RAM, heat, power). To name the exact driver, see `crash-dumps.md`.

Power-transition crashes (0x9F, 0x14F) from USB devices are often avoided by turning off
USB selective suspend and the device's "Allow the computer to turn off this device" option, or
unplugging the device before sleep.

## 5. Network patterns

| Signature | Meaning | Fix |
|---|---|---|
| Gateway < 5 ms, 0% loss; internet loss > 2% or jitter > 50 ms | Upstream: ISP or mobile network | Not a PC fix. On mobile: check data quota/fair-use throttling, signal, dongle placement (USB extension, near a window). |
| Gateway > 10 ms or loss on Wi-Fi | Local Wi-Fi | Move closer, prefer 5 GHz (`wifi.Band`), check `busiestChannels`, update Wi-Fi driver *if* the vendor has a newer one. |
| Upload ≫ download on mobile | Carrier throttling or congested cell | Check plan / time of day. |
| System DNS avg > 150 ms but public DNS fast | Slow resolver (common on hotspots/dongles) | Set DNS per adapter (Wi-Fi and USB modem are different adapters). Reversible. |
| Latency under load − idle latency > 100 ms | Bufferbloat | Router SQM/QoS; on mobile little can be done. |
| `connectionHint` = phone hotspot / USB modem | Mobile link | Results vary with signal and plan; compare with another network before blaming the PC. |
| Adapter rx errors/discards climbing | Driver or link fault | Driver update, different port/cable. |
