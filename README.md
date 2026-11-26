# claude-kit

Skills for engineers who run real systems: give your agent a long-term memory in Obsidian, keep it from touching
production or printing secrets by accident, and learn new topics properly. Plain Markdown, MIT, made to be adapted.

Works in **Claude Code** (as plugins, with hooks and subagents) and in **any agent that reads skills**: Cursor,
Codex, GitHub Copilot, Gemini CLI, OpenCode, Windsurf and more, through [`npx skills`](https://github.com/vercel-labs/skills).

## 30-second setup

**Claude Code:**

```
/plugin marketplace add HirushaUthsara/claude-kit
/plugin install vault-memory@claude-kit
/plugin install infra-ops@claude-kit
/plugin install toolbox@claude-kit
```

Install only the plugins you want. Restart Claude Code once so the hooks load.

To get updates automatically, open `/plugin` → **Marketplaces** → **claude-kit** → enable auto-update (third-party
marketplaces are off by default). Or update by hand with `/plugin marketplace update claude-kit`. Every commit
here is a new version.

**Any other agent** (copies editable files into your project; add `-g` for all projects):

```
npx skills@latest add HirushaUthsara/claude-kit
```

It asks which skills and which agent. Update later with `npx skills@latest update`. Pick one method per agent:
installing both gives every skill twice.

**Then just use it.** There is no config step. The first time a skill needs something about your setup (your vault
folder, your Azure DevOps project, your Study HQ page), it asks once and offers to save the answer in
`~/.claude/claude-kit/`.

## What it fixes

**"I explained this project to the agent yesterday. And the day before."**
Keep project knowledge in an Obsidian vault and let the agent read just the section it needs. `vault` finds and
reads one heading-level section at a time (a few hundred tokens, not whole notes) and writes dated updates back.
In Claude Code, hooks show a project index at session start and point at relevant notes as you type.

**"Where were we?"**
`/handoff` at the end of a session records status, decisions and next steps in the vault and prints a resume
prompt you can paste into any fresh session, on any account or machine.

**"It almost ran that against prod."**
In Claude Code, the infra-ops **security guard** hook asks before production changes, blocks printing secrets
(`.env` files, keys, tokens, connection strings), blocks force-push and `--no-verify`, and logs every cloud and git
change. `azure-ops` and `databricks-ops` add the habits: read state before changing it, explain the blast radius and
the rollback, one approval per irreversible command.

**"The PR review is full of noise."**
`ado-pr-review` reviews an Azure DevOps PR, verifies every finding against the source branch, and posts only what you
approve. It re-checks threads after the author pushes fixes.

**"I want to actually learn this, not skim it."**
`accelerated-learning` tutors one checkable idea at a time from your real baseline. `notebooklm-study` turns
NotebookLM into a study loop with verified sources, quizzes and a progress tracker.

## Reference

### vault-memory

- **[vault](plugins/vault-memory/skills/vault/SKILL.md)**: look up or record project knowledge in an Obsidian vault
  at section level. Ships its own stdlib Python script. Used automatically when a question needs project context.
- **[handoff](plugins/vault-memory/skills/handoff/SKILL.md)** `/handoff`: record where the work stands and print a
  self-contained resume prompt. Needs `vault` installed next to it for the vault part.
- Claude Code only: **vault-scout** agent (answers questions that span many notes without filling your context) and
  hooks (project index at session start, note pointers per prompt, the vault command for subagents).

### infra-ops

- **[azure-ops](plugins/infra-ops/skills/azure-ops/SKILL.md)**: change, deploy and track Azure against a written
  state store (`target` / `intended` / `observed` per resource, drift vs violation, environment parity).
- **[databricks-ops](plugins/infra-ops/skills/databricks-ops/SKILL.md)**: safety tiers for bundles, jobs, pipelines,
  notebooks and SQL; failed-run and deploy workflows.
- **[ado-pr-review](plugins/infra-ops/skills/ado-pr-review/SKILL.md)** `/ado-pr-review <link>`: verified Azure DevOps
  PR review, posted only on approval.
- Claude Code only: agents **code-reviewer**, **log-triage** (read-only incident triage across Azure and Databricks
  logs), **azure-auditor** (read-only drift sweep), and the **security guard** hook.

### toolbox

- **[accelerated-learning](plugins/toolbox/skills/accelerated-learning/SKILL.md)** `/accelerated-learning <topic>`:
  adaptive, visual, one-step-at-a-time tutoring.
- **[notebooklm-study](plugins/toolbox/skills/notebooklm-study/SKILL.md)**: the Study Loop with NotebookLM and a
  Study HQ tracker (the tracker page needs Claude's Artifacts).
- **[antigravity-factory](plugins/toolbox/skills/antigravity-factory/SKILL.md)**: Claude writes the spec and
  verifies; the Antigravity CLI implements, test-first, one cycle at a time.

## Your setup stays yours

The skills hold the method; your facts live in `~/.claude/claude-kit/` (override with `CLAUDE_KIT_DIR`), never in
this repo. Skills create these files when you agree, or you can start from [`examples/claude-kit/`](examples/claude-kit/):

| File | Read by | Holds |
|---|---|---|
| `vault.json` | vault, handoff, hooks | `vault_dir`; `projects`: repo folder → folder under `Projects/` |
| `vault.md`, `handoff.md` | vault, handoff | note naming, status notes, where your repos live |
| `guard.json` | security guard | extra prod/uat name patterns, IDs to watch, protected branches |
| `databricks.md` | databricks-ops, log-triage | environments, CLI profiles, workflows |
| `log-triage.md` | log-triage | apps, subscriptions, infra stores, known traps |
| `ado-pr-review.md` | ado-pr-review | organization, project, repos, clone folder |
| `notebooklm-study.md` | notebooklm-study | your Study HQ URL |
| `antigravity-factory.md` | antigravity-factory | your agy setup and probe settings |

Requirements: Python 3.10+ as `python3` (macOS, Linux) or `python` (Windows) for the vault script and the hooks
(standard library only). On Windows the hooks need Git Bash, which Claude Code uses for hooks when it is installed.
Other tools (`az`, the Databricks CLI, `gh`, the Azure DevOps MCP server, `agy`) only when you use the skill that
needs them. Tested on Windows, macOS and Linux on every push.

## The security guard (Claude Code)

A `PreToolUse` hook on shell commands, file reads and searches:

- **denies** printing secrets: `.env` and credential files, `az ... keys list` / connection strings / Key Vault values
  without a names-only `--query`, `databricks auth token`, env dumps; `git push --force`; `--no-verify`;
- **asks** before production changes (Azure and Databricks writes, `-t prod` deploys, Azure DevOps pipeline runs, PR
  auto-complete), pushes to protected branches, `reset --hard`, `clean -f`, `branch -D`;
- **logs** Azure, Databricks, git and Azure DevOps changes to `~/.claude/audit/<YYYY-MM>.jsonl` (secrets redacted);
- **tells you** when a settings file changes mid-session.

It recognises `prod`/`prd`/`uat` in names out of the box; add names that don't say so in `guard.json`. It is
pattern-based, fails open on internal errors, and ships with 93 self-test cases:

```
python3 -I -S plugins/infra-ops/hooks/guard.py selftest
python3 -I -S plugins/vault-memory/skills/vault/scripts/vault.py selftest
```

## Make it yours

Fork it and edit the Markdown. Each skill is one folder with a `SKILL.md` (name, a description that says when to use
it, then the method) and any files it needs next to it. Keep facts out of skills: put them in a
`~/.claude/claude-kit/` file and have the skill read it.

## License

MIT
