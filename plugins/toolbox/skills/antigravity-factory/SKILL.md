---
name: antigravity-factory
description: Supervise the Antigravity CLI (`agy`, installed in WSL) as the implementer while Claude acts as spec owner, verifier and committer, running a test-first software-factory loop one cycle at a time. Use when the user wants Antigravity/agy/Gemini to build or fix code from a spec (e.g. "use antigravity for this", "orchestrate agy", "run the next factory cycle"), or when continuing a project whose AGENTS.md describes a factory loop driven by Antigravity.
---

# Antigravity factory supervisor

**Roles.** `agy` writes code and tests. Claude writes and amends specs, runs every command that executes code (typecheck, tests, builds, browser probes), verifies against the spec, feeds exact failures back to `agy`, and makes the commits. Claude does not write application code itself. If a fix is needed, it goes back to `agy` as a precise instruction.

## Reference setup (Windows + WSL, verified 2026-10-26 with agy 1.4.7; check yours against it)
If `~/.claude/claude-kit/antigravity-factory.md` exists, read it first: it overrides these facts for this machine.
- `agy` lives at `~/.local/bin/agy` in WSL (Ubuntu). Settings: `~/.gemini/antigravity-cli/settings.json`. The default model is set there; don't override it unless the user asks.
- Keep the terminal sandbox **on**. Inside it, Windows interop (`cmd.exe`, `node.exe`) **hangs** and `.git` is read-only. So `agy` must not run npm/node/cmd.exe/git-write commands. Keep the settings allowlist to read-only tools, read-only git, and `write_file(<repo>)`. Never launch with `--dangerously-skip-permissions`; it is unsafe.
- `--mode auto` may be unavailable on your account. `--mode accept-edits` works, and headless honours it.
- Node only exists on Windows, and `node_modules` holds Windows binaries. Claude runs all npm/node from Git Bash/PowerShell on Windows.
- Call WSL from Git Bash with `MSYS_NO_PATHCONV=1 wsl.exe -e bash <script.sh>`. Write scripts with LF endings (`sed -i 's/\r$//'`), and keep quoting inside script files rather than inline `bash -c` (PowerShell and Git Bash mangle it).
- The repo path in WSL is `/mnt/c/Users/<user>/projects/<repo>`, which contains spaces, so always quote it.

## Files in this skill
- `agy-turn.sh <repo_wsl> <prompt_file_wsl> <out_prefix_wsl> [conversation_id]`: runs one headless turn (stream-json log at `<out>.ndjson`) and prints a summary: conversation id, status, response, files touched, commands attempted, denied actions. Set `AGY_TIMEOUT` (default `45m`). Run it with Bash `run_in_background: true` and wait for the completion notification; don't poll.
- `probe.mjs [seconds] [screenshotPath] [mockupPath]`: copy it into the repo root as `.probe.tmp.mjs`, run `node .probe.tmp.mjs …` on Windows, then delete it. It starts its own Vite server on a free port (never relies on :5173, which may be the user's dev server), launches headless Edge (`channel: 'msedge'`), samples the app's diagnostics object (`window.__DIAGNOSTICS__`, or the global named in `PROBE_GLOBAL`) once a second, and prints min/max/final of every numeric field plus console errors. The app has to publish that object (a dev-only `window.__DIAGNOSTICS__ = {...}` updated each frame or tick). Optionally it screenshots the app and a mockup at 1280×800 and 390×844.

## The loop (one cycle per run; never batch cycles)
1. **Pre-flight.** `git status` must be clean, or contain only known work-in-progress you've decided to keep. Note `git log -1`. Re-read the cycle's spec section and acceptance criteria.
2. **Red turn (new conversation).** Prompt `agy`: restate the cycle's acceptance criteria; write failing tests named with their IDs; no implementation changes; do not run npm/node/cmd.exe/git commit (the supervisor runs them); end with a list of files changed. Then Claude runs the new tests and checks that **each ID fails, and fails for the right reason**. A test that passes on unfixed code, or fails only because of a missing import, isn't red; send it back.
3. **Green turns (same conversation, `--conversation <id>`).** Prompt: implement Step 3, followed by the exact failing output (trimmed). After each turn Claude runs `npm run typecheck` and `node node_modules/vitest/vitest.mjs run`. At most 3 green rounds; then escalate to the user with the evidence.
4. **Integrity review (Claude).** Read `git diff`:
   - tests deleted, `.skip`/`.only`, loosened `expect`s, lowered thresholds, assertions wrapped in `if`, API aliases added only to satisfy a test, stray `@ts-expect-error`, lint exceptions, edits outside the allowed paths, dependency changes.
   Any of these goes back to `agy`.
5. **Behaviour (Claude).** `npm run test:prod`. Then run `probe.mjs` for ≥ 10 s and judge the trace, not one sample. For UI cycles, compare side-by-side screenshots with the mockup. Feed the problems back as a green turn.
6. **Docs turn (same conversation).** `agy` ticks the boxes in the status file, fills the spec's tuned-constants table with the evidence Claude measured, and updates the README if needed.
7. **Commit (Claude).** Stage explicit paths only (never `git add -A` if unrelated work exists). Message `fix(cycle-N): …` or `feat(cycle-N): …` with a body listing the IDs and the verification evidence, ending with the session's attribution lines. Never push.
8. **Report to the user** in a few lines: what passed, the measured numbers, anything deferred. Then start the next cycle, unless a spec or design checkpoint says to stop.

**Spec amendments.** When verification shows the spec was wrong or vague, Claude edits the spec (not `agy`) and commits that separately as `docs(...)` before the next turn.

## Prompt template for agy turns
```
You are the implementer in a supervised software factory. Repo: <repo>. Read AGENTS.md, <status file>, <spec> §<n>.
Task (this turn only): <red | green | docs> for Cycle <N>: <IDs>.
Hard limits:
- Do NOT run npm, npx, node, cmd.exe, powershell.exe, or git add/commit/push: they hang or are denied in your sandbox. The supervisor runs every test and commit and will send you the results.
- Read-only shell tools and read-only git are fine. Edit files only inside the repo.
- Never weaken, skip, or delete a test; never add API aliases or lint exceptions to satisfy a test.
- <cycle-specific constraints from the spec>
<For green turns: "Current failures from the supervisor's run:" + trimmed output>
Finish with: (1) files changed, (2) what you expect the supervisor's next test run to show, (3) open questions.
```

## Pitfalls already seen (check for them every cycle)
- **In headless mode, any denied command ends the turn immediately with no edits** (stderr: "a tool required the 'command' permission…"). Put the exact allowed shell commands in every prompt, tell `agy` to prefer its built-in read/search/edit tools, and check `denied:` in the summary. If a turn died this way, resume the same conversation rather than starting over.
- Red tests sampled once after a delay passed on buggy code. Require per-frame recording, or event-window assertions.
- A one-sample behaviour check hid a collapse at about 4 s. Always use ≥ 10 s traces.
- Parallel browser tests timed out under load. Run them serially, with generous timeouts.
- Agents stop after a cycle even when told to continue. That's fine here, because Claude drives one cycle per run.
- The agent "fixed" tests by adapting the API to the test (aliases). Reject this.
- `spawn('npx.cmd')` fails with EINVAL on Node ≥ 18.20. Use `process.execPath` with the package's JS entry point.
