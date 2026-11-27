---
name: windows-perf-diagnosis
description: Evidence-based, read-only performance and health diagnosis for Windows PCs and laptops, ending in a short, prioritised report in chat. Use this whenever someone says their Windows machine is slow, laggy, freezing, stuttering, crashing or blue-screening, apps take long to open, the fan is always loud, the disk or memory is "always at 100%", the battery drains fast, or the internet feels slow on that machine — and also when they ask "is my CPU or RAM the bottleneck?", "should I buy more RAM / a new laptop?", "what's eating my disk space?", "why does my PC keep restarting?", or want a general health check or before/after comparison. Diagnoses only; it never changes the system. Not for macOS/Linux, and not for writing or optimizing application code.
---

# Windows performance diagnosis (Phase 1: diagnose and report)

You are diagnosing someone's own Windows machine. The value you add is not a list of
generic tweaks — "optimizer" tools already do that badly. The value is **finding the
actual cause with evidence**, explaining it plainly, and telling the person exactly what
to do about it, in priority order, without breaking anything.

This skill is **read-only**. Every bundled script only reads. You recommend fixes; you
do not apply them. If the person later wants help applying a fix, treat that as a
separate task outside this skill: one change at a time, explicit approval for each,
a restore point first, and verification afterwards.

## Ground rules (and why)

- **Measure before concluding.** Every claim needs a number or a log entry behind it.
  People act on this — buying RAM, uninstalling software — so a plausible guess is worse
  than "not checked".
- **Only report state you verified.** Before saying something is installed, running or
  starting with Windows, check it actually is (a Run-key entry can be disabled; software
  you remember from earlier may be gone; `vmmem` isn't always WSL). Wrong facts about
  someone's own machine destroy trust in everything else in the report.
- **Never request administrator elevation, install software, or change settings** without
  asking first. Phase 1 doesn't need any of them. Checks that need admin go under
  "Not checked" instead of being guessed.
- **A failed read is not a zero.** Non-elevated queries often come back empty. Report those
  as "not checked", never as "0" or "disabled". See `references/pitfalls.md`.
- **Don't measure while you're measuring.** Run scripts one at a time and never take
  performance samples while another script is running — your own work skews the numbers.
- **Privacy.** Never print BitLocker recovery keys, product keys, serial numbers or service
  tags, MAC addresses, Wi-Fi passwords, or personal file contents. People paste these
  reports into forums and chats, so leave out the computer name, Wi-Fi network names, IP
  addresses and the username (write paths as `%USERPROFILE%\...`).
- **Measure the symptom, don't assume it.** If someone says "disk is always at 100%" and it
  isn't now, say what you measured, look for traces in the logs, and give a capture plan
  (see `references/symptoms.md`, last section). Agreeing with an unverified premise sends
  people after the wrong fix.
- **Every machine is different.** Gaming desktops, old HDD laptops, budget eMMC machines and
  new ultrabooks fail in different ways. Let this machine's evidence pick the cause.
- **Correct yourself openly** in one plain line if later evidence contradicts something you said.

## Workflow

### 0. Ask once, briefly

Before running anything, ask (one round, use AskUserQuestion if available):

1. **Symptoms** — when it's slow (always / after boot / under load / randomly) and what it
   looks like (freezes, slow app launches, one app, crashes/restarts, slow internet, battery).
2. **What they use the machine for** — this decides what "enough" means.
3. **Permission for the optional tests**, each of which costs something:
   - CPU load test: ~2 min of 100% CPU; ask them to plug into AC for a fair result.
   - Network throughput test: transfers roughly 25–40 MB. Skip or ask on mobile data,
     a phone hotspot or a capped plan.
   - Storage scan: 1–5 minutes of disk activity.

If the request already answers these, or you can't ask, proceed with safe defaults: run the
core snapshot, skip throughput on metered/hotspot/USB-modem connections, and skip the load
test unless the question is about CPU or future workloads.

### 1. Run folder

Use the folder the person or task specifies; otherwise
`%USERPROFILE%\Documents\windows-perf-diagnosis\<yyyy-MM-dd_HHmm>\` for the raw JSON. If an
earlier run's `snapshot.json` exists in the parent folder, compare against it (before/after).

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_SKILL_DIR}\scripts\collect.ps1" -OutFile "<run>\snapshot.json"
```

`${CLAUDE_SKILL_DIR}` is the folder this SKILL.md is in (Claude Code fills it in; elsewhere use that folder's
path). Run the optional scripts below the same way.

### 2. Core snapshot (always) — `scripts/collect.ps1`

~1 minute. Collects system/OS, power source and mode, battery wear, memory modules, commit,
pagefile, kernel pool and compression, 10 live samples (CPU, run queue, speed vs base,
available RAM, paging, disk latency), top processes, `vmmem` owner, disk volumes/health,
update caches and `Windows.old`, crashes and unclean shutdowns (30 days), pending reboot and
update failures, services failing at boot, grouped system errors, app crashes and hangs,
antivirus state (including broken third-party AV filter drivers and Defender detections),
unsigned programs running from user folders, "PC optimizer" tools, virtualization conflicts,
OEM agents, startup entries with their real enabled state, per-process disk I/O and handle
counts, system drive type (HDD/SSD/eMMC), Fast Startup and hibernation, display and game
settings, problem devices, drivers, and the active connection including whether Windows
treats it as metered.

Read `snapshot.json` in full. Check `system.uptimeHours` first: under ~15 minutes means boot
settling (say so or resample); many days or a pending reboot means some findings may clear on
reboot.

### 3. Optional tests — one at a time, only with permission

| Script | When |
|---|---|
| `storage-scan.ps1 -OutFile <run>\storage.json` | disk space low or asked about |
| `network-test.ps1 -OutFile <run>\network.json [-SkipThroughput]` | internet complaints or general check |
| `load-test.ps1 -OutFile <run>\load.json [-Seconds 120]` | CPU or future-workload questions |

Sustained CPU clocks vary between runs (heat, workload, what ran just before) — on one
laptop the same chip measured 2.3–3.3 GHz on different runs. Report the measured range and
the conditions (power source, power mode, how long it ran), not one number as "the speed".

### 4. Interpret — read the references

- `references/symptoms.md` — **start here**: for each symptom (slow boot, 100% disk, high CPU,
  freezes, gaming stutter, blue screens, battery drain, Wi-Fi, low space, malware, audio/USB,
  old hardware…) the likely causes in order and which fields confirm them.
- `references/interpretation.md` — thresholds, and a catalogue of culprits with their
  signatures and fixes.
- `references/pitfalls.md` — ways this diagnosis has gone wrong before. Read it before writing
  conclusions; several of those mistakes look completely reasonable.

Also check the evidence for problems the person didn't mention — a failing drive, malware
signals or repeated crashes matter even if they asked about something else.

- **Find the bottleneck by elimination**, and say what you ruled out (e.g. "CPU is not the
  cause: run queue 0 in every sample").
- **Follow up with targeted read-only queries** to confirm a finding before reporting it.
- **Separate "now" from "under load"** — an idle sample says nothing about heavy work.
- **State confidence** for causes you can't prove (e.g. a crash with no readable dump).
- Crash dumps: `references/crash-dumps.md` explains naming the exact driver — needs WinDbg
  and admin, so ask first.

### 5. Report — in chat, short and scannable

The deliverable is the chat message itself — don't write separate report files.
Aim for **roughly 400–700 words**; the person can always ask for more detail, but they
won't read a wall of text. Say each number once — don't repeat the same evidence in the
verdict, the scorecard and the findings.

Use this structure:

```markdown
## Verdict
2–3 sentences: the main cause(s), what it is NOT, and whether the fix is free or needs money.

## Scorecard
| Area | Measurement | Status |
|---|---|---|
(6–10 rows, only areas that matter. Status: ✅ fine · ⚠️ watch · ❌ problem.
 Add a "Before" column when comparing with an earlier run.)

## What's wrong (most important first)
**1. Title (high/medium/low)** — one line of evidence with the key numbers.
What it means, in one plain sentence. → Fix: step N.
(At most ~5 findings. Group minor items into one line at the end.)

## What to do, in order
| # | Action | Cost | Reversible | How |
|---|---|---|---|---|
(Free, safe, high-impact first. Hardware last unless it's the real fix. Exact click path
 or command in "How". Mark anything that deletes data as not reversible.)

## Not checked
One short line per item (needs admin / skipped and why).
```

If the environment discourages emoji, use plain words (OK / Watch / Problem) in the Status
column instead.
