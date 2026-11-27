# Symptom playbook

Start from what the person describes, then check the likely causes **in this order** — most
common and cheapest to confirm first. Field names refer to `snapshot.json`. Thresholds and the
fix for each culprit are in `interpretation.md`.

Contents: General slowness · Slow boot/login · 100% disk · High CPU / fan / heat · Memory full ·
Freezes and stutter · Gaming / video performance · Blue screens and restarts · One app slow or
crashing · Slow after an update · Battery drain · Slow internet / Wi-Fi drops · Low disk space ·
Suspected malware or pop-ups · Audio crackle / USB drop-outs · Old or budget hardware ·
When the symptom isn't happening now

Every machine is different: a gaming desktop, a five-year-old HDD laptop and a new ultrabook fail
in different ways. Let the evidence pick the cause; don't assume it is the same as last time.

## General slowness ("everything is slow")
1. **System drive is an HDD or eMMC** (`disk.systemDrive.mediaType`/`busType`). On an HDD this is
   usually *the* answer; an SSD is the single biggest upgrade such a machine can get.
2. **Memory full** — available RAM, commit %, sustained paging (see "Memory full").
3. **Background load** — `processes.topByCpuLast5s`, `topByDiskIO`: indexing, OneDrive/Google
   Drive sync, Defender scanning, Windows Update (`TiWorker`, `MoUsoCoreWorker`), browser tabs.
4. **Two antivirus products / a broken one** (`security.*`, `software.thirdPartyAntivirus`).
5. **OEM agents and startup apps** that are actually enabled.
6. **Power mode capping the CPU** (`power.modeOnAC`), especially on battery.
7. **Thermal throttling** — only visible under load; offer the load test.

## Slow boot or slow login
1. Enabled startup entries (`software.startupEntries` where `enabled`), OEM agents, updaters.
2. HDD system drive.
3. Pending reboot / update servicing (`updates.*`) — the next few boots are slow until it finishes.
4. Fast Startup (`power.fastStartupEnabled`): on = faster cold boot but stale driver state; if
   problems clear only after "Restart" (not shut down), Fast Startup is the reason.
5. Services failing or timing out at boot (`serviceFailuresThisBoot`, event 7000/7009/7011).
6. Exact boot-time breakdown needs admin (Diagnostics-Performance log) — list as not checked.

## "Disk is always at 100%"
1. Check `live.summary.diskIdlePct` and latency: is it actually busy *now*? If not, see
   "When the symptom isn't happening now".
2. HDD system drive — 100% active time on an HDD is common even under light load.
3. Who is doing the I/O: `processes.topByDiskIO` (indexer, sync clients, Defender, updates,
   browser cache, game launchers).
4. Paging: memory pressure turns into disk load — high pages/sec with low available RAM.
5. Failing drive: health not "Healthy", disk errors in `systemErrors7d` on the *system* disk
   (map `\Device\HarddiskN`; USB devices log the same errors harmlessly).

## High CPU, loud fan, laptop hot
1. Which process: `processes.topByCpuLast5s`. Common: `MsMpEng` (Defender scan), `SearchIndexer`,
   `TiWorker`/`MoUsoCoreWorker` (updates), `WmiPrvSE` (a monitoring tool polling WMI), browser,
   `dwm` (display driver), game launchers, crypto-miners (high CPU from an unknown or unsigned
   process — cross-check `security.unsignedProcessesInUserFolders`).
2. Sustained run queue > 2 × cores = genuinely CPU-bound.
3. Heat: load test — falling MHz over time with throttle events means cooling can't keep up
   (dust, blocked vents, soft surfaces, dried thermal paste, failing fan). Software can't read
   most laptop temperatures without vendor tools; say so.
4. Power mode "Best performance" makes fans louder by design.

## Memory full
1. Commit % and available RAM vs installed RAM; pagefile growth (`commitLimitGB` far above RAM).
2. Who: `processes.topByPrivateMemory` — browsers, Electron apps, IDEs, `vmmem` (find its owner),
   games.
3. Leaks: a process whose memory or handle count is far out of line (`processes.topByHandles`;
   > 10,000 handles in one non-system process is suspicious), kernel pool high
   (`memory.kernelNonpagedPoolMB`) — leaked handles and driver allocations live there.
4. Is the RAM itself the ceiling? 4–8 GB with modern browsers + any dev/creative tool usually is.

## Freezes and stutter (system-wide, a few seconds)
1. Memory pressure (above) — the most common cause.
2. Disk stalls: HDD, failing drive, a USB storage device or network drive that Explorer waits on.
3. Antivirus filter drivers (especially broken or duplicate ones).
4. Driver problems: GPU driver resets (event 4101 "display driver stopped responding"), Wi-Fi
   or USB drivers (`systemErrors7d`, NDIS resets).
5. App hangs (`stability.appCrashesAndHangs14d`) — if only one app hangs, it's that app.

## Gaming / video performance (low FPS, stutter)
1. Which GPU is in use: laptops with two GPUs often run games on the integrated one. Check
   `drivers.gpus` and advise Settings → System → Display → Graphics → set the game to
   "High performance".
2. GPU driver age vs the vendor's current one (verify the vendor's latest before advising).
3. Power: on battery or "Best power efficiency" caps both CPU and GPU.
4. Background recording on (`display.backgroundRecording`) costs performance on weaker GPUs.
5. Thermal throttling (load test), RAM single-channel (integrated graphics lose up to half their
   bandwidth), memory pressure, HDD for game files (stutter while loading assets).
6. Refresh rate (`display.screens[].refreshHz`) — a 144 Hz screen set to 60 Hz feels choppy.
7. A per-frame GPU measurement needs the game itself or tools like PresentMon; list as not
   checked.

## Blue screens and random restarts
1. `stability.bugchecks30d` (code + parameters) and `uncleanShutdowns30d` — use the bugcheck table
   in `interpretation.md`. Kernel-Power 41 with code 0 = hang/power loss, not a BSOD.
2. Same code every time → one driver; mixed codes → hardware (RAM, heat, power supply), and
   `whea30d` > 0 points at hardware.
3. Timing: during sleep/wake → power-state drivers (USB, network, AV filters); under load →
   heat or power; at random with mixed codes → test RAM (Windows Memory Diagnostic, user runs it).
4. Name the driver from the dump only with consent (`crash-dumps.md`).

## One app slow or crashing
1. `stability.appCrashesAndHangs14d` for that app.
2. Its memory/handles; add-ins/extensions (Office add-ins, browser extensions) — ask the person
   to try a clean profile or safe mode of that app.
3. Antivirus scanning its files (dev tools with `node_modules`, game folders).
4. If the whole machine is fine, say so plainly — fix the app, not Windows.

## Slow after a Windows update
1. Update still finishing: pending reboot, `TiWorker`/indexer busy, `Windows.old` fresh.
2. A driver replaced by Windows Update (GPU, Wi-Fi, storage) — check driver dates.
3. An app or AV incompatible with the new build (services failing since the update date).
4. Rollback is possible only while `Windows.old` exists (10 days by default).

## Battery drains fast or in sleep
1. `battery.healthPct` — a worn battery simply holds less.
2. Background CPU (top processes), screen brightness and refresh rate, power mode.
3. Sleep drain: Modern Standby keeps network devices active; USB modems and some Wi-Fi drivers
   keep it awake. `powercfg /sleepstudy` (admin) shows what — list as not checked or ask.
4. Hibernate available (`power.hibernateEnabled`) lets the laptop stop draining overnight.

## Slow internet / Wi-Fi drops
Run `network-test.ps1`. Then: gateway latency/loss (local link) vs internet (upstream) — see
`interpretation.md` §5. Also Wi-Fi band and signal, VPN adapters, proxy, DNS speed, metered
status on capped plans, `wifiDisconnects7d`, adapter errors. Phone hotspots and USB modems vary
by signal and time of day — compare with another network before blaming the PC.

## Low disk space
Run `storage-scan.ps1`. Usual suspects: `Windows.old`/update leftovers, pagefile growth from
memory pressure, hibernation file, VM and container disks (`.vhdx`, `.vdi`), game libraries,
SDKs/editors (Unity, Android, Anaconda), duplicate Python environments, browser profiles, cloud
sync caches, Downloads, System Restore (admin). Suggest moving large data to another drive;
mark anything that deletes data as not reversible.

## Suspected malware, adware or pop-ups
1. `security.unsignedProcessesInUserFolders` — unsigned programs running from Temp/AppData/
   Downloads are a red flag (not proof; some small tools are legitimately unsigned).
2. `security.defenderDetections30d`, Defender real-time protection on, signatures current.
3. Unknown startup entries; browser-based pop-ups usually come from site notification permissions
   or extensions, not Windows.
4. "PC optimizer" / driver-updater tools (`software.optimizerTools`) are a frequent source of
   nags, bundled software and instability; recommend removing them.
5. Recommend a full Defender offline scan (the person runs it); never remove files yourself.

## Audio crackling, USB devices disconnecting
1. High DPC latency from a driver (often Wi-Fi, GPU, or ACPI/battery drivers) — measuring needs
   LatencyMon; suggest it and list as not checked.
2. USB selective suspend (`power.usbSelectiveSuspend*`) and the device's power-management
   option; hubs without their own power.
3. Driver errors in `systemErrors7d`.

## Old or budget hardware
Be honest when the hardware is the ceiling: 4 GB RAM, HDD or eMMC storage, dual-core or Celeron/
Pentium/Atom CPUs, < 10% free space. Give the free improvements, then the one upgrade that matters
most (usually SSD first, then RAM), and when replacement is the sensible answer. Don't oversell
tweaks on a machine that is simply too slow for its workload.

## When the symptom isn't happening now
If the person reports something (100% disk, freezes, high CPU) that the measurements don't show:
- Say so plainly — don't confirm the premise without evidence, and don't invent a cause.
- Look for traces of it in the logs (crashes, hangs, update activity, errors at the times they
  mention).
- Give a short capture plan: when it happens, open Task Manager (Ctrl+Shift+Esc) → Processes,
  sort by the busy column and screenshot it, or note the time so the event logs can be checked;
  then run this diagnosis again during the problem.
