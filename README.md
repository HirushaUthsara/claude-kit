# claude-kit

Claude Code plugins I use every day, made generic: project memory in an Obsidian vault, safer cloud and
delivery work, and learning tools.

| Plugin | What you get |
|---|---|
| **vault-memory** | `vault` skill (find/get/log at section level, so Claude reads a few hundred tokens instead of whole notes), `handoff` skill (records status in the vault and prints a resume prompt for a fresh session), `vault-scout` agent, and hooks: a project index at session start, relevant-note pointers on each prompt, and the vault command for subagents. |
| **infra-ops** | `azure-ops` (change and track Azure against a written state store with target/intended/observed per resource), `databricks-ops` (safety tiers for bundles, jobs, notebooks, SQL), `ado-pr-review` (Azure DevOps PR review with verified findings, posted only on approval), agents `code-reviewer`, `log-triage`, `azure-auditor`, and a **security guard** hook. |
| **toolbox** | `accelerated-learning` (adaptive one-step-at-a-time tutoring), `notebooklm-study` (NotebookLM study loop with a Study HQ tracker artifact), `antigravity-factory` (Claude as spec owner and verifier, the Antigravity CLI as implementer, test-first). |

## Install

In Claude Code:

```
/plugin marketplace add HirushaUthsara/claude-kit
/plugin install vault-memory@claude-kit
/plugin install infra-ops@claude-kit
/plugin install toolbox@claude-kit
```

Or add [`examples/settings.json`](examples/settings.json) to `~/.claude/settings.json`.

Requirements: `python` (3.9+) on PATH for the hooks and the vault script (stdlib only). The skills call `az`, the
Databricks CLI, `gh` or the Azure DevOps MCP server only when you use them.

## Your facts stay on your machine

The plugins hold method, not facts. Anything specific to you (vault location, prod resource names, workspace hosts,
repos, known traps) goes in `~/.claude/claude-kit/` (override with `CLAUDE_KIT_DIR`), which the skills and hooks
read at run time. Start from [`examples/claude-kit/`](examples/claude-kit/):

| File | Used by | Holds |
|---|---|---|
| `vault.json` | vault script, hooks | `vault_dir`, and `projects`: repo folder name → folder under `Projects/` in the vault |
| `vault.md`, `handoff.md` | vault, handoff | your note naming, status notes, where repos live |
| `guard.json` | security guard | extra prod/uat name patterns, IDs to watch, protected branches |
| `databricks.md` | databricks-ops, log-triage | environments table, profiles, where the CLI runs, workflows |
| `log-triage.md` | log-triage | apps, subscriptions, infra stores, timezone, known traps |
| `ado-pr-review.md` | ado-pr-review | org, project, repos, clone location, known-issue notes |
| `notebooklm-study.md` | notebooklm-study | your Study HQ artifact URL |

Every file is optional; without one, the skill discovers what it can and asks you for the rest.

## The vault

`vault.py` indexes every heading section of your vault (BM25, cached, incremental) and serves:

```
python -I -S <plugin>/scripts/vault.py find <words> [-n N] [-p PROJECT]   # ranked pointers, no content
python -I -S <plugin>/scripts/vault.py get "<Note>" ["<heading>"]         # one section, or the outline
python -I -S <plugin>/scripts/vault.py log "<Note>" "<text>"              # dated line under ## Updates
```

Notes under `Projects/<name>/` belong to project `<name>`. With no vault configured, the hooks stay silent.

## The security guard

A `PreToolUse` hook on shell commands (and `Read`/`Grep`) that:

- **denies** printing secrets: `.env` and credential files, `az ... keys list` / connection strings / Key Vault
  values without a names-only `--query`, `databricks auth token`, env dumps; `git push --force` and `--no-verify`;
- **asks** before production changes (Azure writes, Databricks writes, `-t prod` deploys, Azure DevOps pipeline
  runs, PR auto-complete), pushes to protected branches, `reset --hard`, `clean -f`, `branch -D`;
- logs Azure / Databricks / git / Azure DevOps changes to `~/.claude/audit/<YYYY-MM>.jsonl` (secrets redacted);
- tells you when a settings file changes mid-session.

It is pattern-based (it reads the command text and any `.sh`/`.ps1` it runs), fails open on internal errors, and
ships with a self-test of 93 cases:

```
python -I -S plugins/infra-ops/hooks/guard.py selftest
python -I -S plugins/vault-memory/scripts/vault.py selftest
```

## License

MIT
