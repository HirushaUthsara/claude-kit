---
name: handoff
description: End-of-task handoff. Records where the work stands in the user's Obsidian vault (status, decisions, open items, next step, branch/PR/run/resource IDs) and prints a self-contained resume prompt for a fresh session. Use whenever the user says handoff, wrap up, save progress, "I'll continue later/tomorrow", end of day, is switching to another task, is about to /clear or close the session, or is moving the work to another account or machine. Also offer it yourself when a long session reaches a natural stopping point or the context is getting full. Not for capturing a single fact mid-task (the vault skill covers that).
---

# Handoff

The next session, possibly in another account where this conversation does not exist, should resume
with one paste and no re-explaining. Two outputs make that work: **vault entries** (durable, found
by the SessionStart index and prompt hook) and a **resume prompt** (portable, self-contained).

If the user only wants the prompt, skip step 2. If no vault is configured, do steps 1 and 3 only.

**Local conventions:** if `~/.claude/claude-kit/handoff.md` exists, read it first (where repos live, how to find
the open PR, which note gets the status line). If it doesn't and you had to work one of these out, offer to save it
there in a line or two.

## 1. Gather the state (read-only, cheap)

- Repo: current branch, `git status -sb`, `git log -3 --oneline`. Note uncommitted or unpushed work;
  do not commit or push unless the user asks.
- Open PR for the branch: `gh pr view --json number,url,state` on GitHub, or the Azure DevOps MCP
  (`repo_pull_request` action `list` with `sourceRefName: refs/heads/<branch>`). Skip if neither is available.
- From this conversation: what was done and **verified** (say how), what is assumed, decisions and
  why, what is open or blocked and on whom, the single next step, traps discovered, and the IDs the
  next session will need (PR, work item, job run, revision, pipeline, resource names).

## 2. Record in the vault (follow the `vault` skill's capture rules)

```
PY='python -I -S "<this skill's base directory>/../vault/scripts/vault.py"'
```

(The `vault` skill must be installed next to this one; the `Vault script:` line from the SessionStart hook gives the
same command.)

The repo maps to a vault project through `projects` in `~/.claude/claude-kit/vault.json`. A repo with no mapping
has no vault home: skip to step 3 and say so.

1. **Status line**, one `log` to the project's status note (find it with `$PY find status open items -p "<project>"`):
   `Handoff (<branch>): <where it stands>. Next: <step>. Open: <blocker, owner>. Refs: <PR/run/rev IDs>.`
   One line, under ~400 characters. This is what the next session's vault hook will surface.
2. **Each decision, deploy, finding or status change** from this session that is not recorded yet:
   its own `log` line in the most specific note (`$PY find <words>` to locate it). If the session
   already logged it, don't log it again.
3. **New trap or gotcha**: where the next person would look before repeating the mistake (the
   relevant runbook note, or an infra store's `HAZARDS.md`).
4. Small corrections to stale vault text: edit per the vault rules. Larger rewrites: don't do them at
   the end of a session; list them under "Vault corrections pending" in the resume prompt.

Names of secrets only, never values.

## 3. Print the resume prompt

A fenced block the user can paste anywhere, at most ~25 lines. Make it stand alone: no "as we
discussed", full repo path, exact IDs.

```
Resume: <task> in <repo> (<full repo path>), branch <branch> @ <short sha>[, PR <id>]
State:
- <done and verified, with how>
- <in progress / uncommitted files>
Decisions: <decision — why> (one per line)
Next: <the very next concrete step>
Open / blocked: <item — owner>
Read first: vault.py get "<Note>" "<heading>"  (1-3 pointers, smallest sections)
Don't: <traps learned this session>
[Vault corrections pending: <note › section — what's wrong>]
```

## 4. Close

Tell the user in one or two lines what was recorded where, then suggest `/clear` (or closing the
session) now that the state is saved. Don't clear anything yourself.
