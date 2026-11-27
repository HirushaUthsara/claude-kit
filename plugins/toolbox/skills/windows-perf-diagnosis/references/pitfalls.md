# Pitfalls — mistakes this diagnosis has actually made

Every item here happened in a real diagnosis. Each one looked reasonable at the time.
Read this before writing conclusions.

## Reading the system

- **A failed read looks like "zero" or "off".** Without admin, `C:\Windows\Prefetch` lists as
  0 files (it had 292), `Get-MMAgent` fails, and memory-compression settings read as all-False
  while SysMain is stopped (they were all True once it ran). Treat empty/false from a
  permission-limited source as *unknown*, and re-check the dependency (is the service running?)
  before reporting anything as disabled.
- **SMBIOS lies about RAM slots.** It reported 8 slots / 128 GB max on a 2-slot laptop.
  Use the manufacturer's spec sheet for upgrade advice.
- **"Processor Frequency" is nominal, not live.** A CPU reported at 1,690 MHz was turbo-ing
  at 108–175%. And it changes with power source (1,429 on battery). Use % Processor Performance.
- **An idle sample can't judge a CPU for heavy work.** "Not the bottleneck now" was true; the
  load test then showed clocks held at ~1.3 GHz by the power mode — fixed for free to ~2.3 GHz.
  Record power source and power mode with every CPU conclusion.
- **Old date ≠ outdated driver.** A 2022 Wi-Fi driver was already newer than anything the
  laptop vendor offered. Check the vendor's current version before recommending an update.
- **Not every error is the disk.** 40+ `disk` controller errors came from a 4G dongle's tiny
  internal storage, not the SSD. Map `\Device\HarddiskN` to the physical device first.
- **Kernel-Power 41 isn't always a crash.** BugcheckCode 0 after a normal restart request =
  a shutdown that hung or lost power.
- **Locale.** Counter names, `netsh` and `robocopy` labels are translated on non-English
  Windows. The scripts fall back where they can; if a section is empty, suspect locale, and
  say so instead of guessing.

- **`vmmem` isn't always WSL.** A 3 GB `vmmem` with no WSL distro running belonged to the
  Claude desktop app's VM — advice to run `wsl --shutdown` would have freed nothing. Use
  `virtualization.vmmem.likelyOwner`.
- **A Run-key entry isn't a startup app.** Docker, Notion, Adobe and Edge were listed as
  "starting with Windows" while all were disabled in StartupApproved. Use the `enabled` field.
- **Don't report software from memory.** VirtualBox, HAXM and SmartByte were reported as
  installed weeks after they were removed. Only report what this snapshot shows.

## Measuring

- **Your own tools skew the numbers.** A storage scan running alongside sampling produced
  "97% CPU, 29,000 pages/sec" that was entirely self-inflicted. Never sample performance while
  another script runs; if you did, discard and resample.
- **Boot settling.** In the first ~15 minutes after boot, CPU and paging spike. Note uptime.
- **One sample is an anecdote.** Use medians across samples; mention max separately.
- **Throughput servers fail.** One speed-test server returned 403 for a 15 MB request; another
  was 5× slower than the third. Use two or more and report the range.
- **Sustained CPU clocks vary run to run.** The same laptop measured ~2.3, 2.45 and 3.0–3.3 GHz
  all-core in different runs (heat soak, workload type, what ran just before). Report a range
  with conditions; don't call one run "the speed".
- **Mobile links vary hour to hour.** The same USB dongle gave 7.4 Mbps one day and 0.3–1.5 the
  next. Don't call a modem faulty from one test.

## Concluding

- **Don't trust exit codes; verify state.** An uninstaller returned 0 while removing nothing.
  Confirm with the actual driver list, registry and files.
- **Verify your verification.** A check for "HAXM" missed a product whose display name was
  "Intel® Hardware Accelerated Execution Manager". Match on more than one property.
- **The dump beats the hunch.** Antivirus and Wi-Fi were the suspects for repeated 0x9F crashes;
  the dump named the USB modem driver. Say "suspected" until evidence names the cause.
- **Rollback windows move.** A 902-day-old staging folder was safe to delete — until an update
  that night created a fresh `Windows.old`, which then *was* the rollback. Re-check ages
  immediately before advising deletion.
- **Freed space can be re-consumed.** ~50 GB freed by an update was immediately taken by the new
  `Windows.old`; later a growing pagefile ate 5 GB. Explain the mechanism, not just the number.
- **Respect what the person needs.** A "bloat" startup item was the helper for the modem they
  use daily. Ask before labelling something removable.
- **When you were wrong, say so plainly** in one line and move on.

## Safety and privacy

- **Never run `manage-bde -protectors -get`** — it prints the BitLocker recovery password in
  clear text (this happened, and the key landed in a log file). If BitLocker status matters,
  use protector *types* only, and point the person to account.microsoft.com/devices/recoverykey.
- **Before any Safe Mode advice**, have the person confirm they can retrieve their BitLocker key.
- **Recycle Bin capacity is per drive** (often 5–10%). Anything bigger is deleted permanently
  — say so when recommending a big cleanup.
- **Crash dumps contain memory contents.** If you copy one to analyse it, delete the copy after.
- **No admin, no installs, no setting changes** in this skill. If a check needs admin, list it
  under "Not checked".

## PowerShell 5.1 gotchas (for follow-up queries you write yourself)

- Single-letter helper names collide with aliases (`r` = Invoke-History, `h` = Get-History);
  aliases win over functions. Use descriptive names.
- `$host` is reserved — `foreach ($host in ...)` silently fails.
- No `&&`, `||`, ternary or `??`. Use `;` and `if`.
- `2>&1` on native commands turns stderr into errors; avoid it.
- Paths over 260 characters fail silently (e.g. a debugger symbol cache under a deep temp
  folder); keep tool working folders short.
