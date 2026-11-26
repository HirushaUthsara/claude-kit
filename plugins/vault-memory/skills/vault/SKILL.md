---
name: vault
description: Look up or record project knowledge in the user's Obsidian vault at section level, so only the few hundred tokens needed are read. Use whenever a question needs project context (infra, code behaviour, decisions, incidents, findings, history, runbooks), when a vault pointer appears in context, or when a decision/deploy/finding/status changes and should be recorded. Not for general coding questions.
---

# Vault: section-level recall and capture

The vault is the **single home for project knowledge**. Notes can be large, so **never Read a whole note**.
Everything goes through one script that ships in this skill's folder, `scripts/vault.py` (stdlib Python 3.10+).
Below, `$PY` stands for this command prefix:

```
python3 -I -S "${CLAUDE_SKILL_DIR}/scripts/vault.py"
```

`${CLAUDE_SKILL_DIR}` is the folder this SKILL.md is in (Claude Code fills it in; elsewhere use that folder's
path). Use `python` where `python3` doesn't exist (usually Windows). Keep the quotes: the path may contain spaces.
In Claude Code the SessionStart hook also prints the exact command as `Vault script: ...`.

## First use (the script says "No vault configured")

1. Ask the user for the vault folder (the one that contains `.obsidian/`). Don't guess or search the disk.
2. Check it exists and holds `.md` notes. Project notes are expected under `Projects/<project name>/`; if the vault
   is organised differently, say so (notes outside `Projects/` still work for find/get, just without a project).
3. Ask which code repos map to which project (optional): repo folder name → folder name under `Projects/`.
4. Write `~/.claude/claude-kit/vault.json`:
   `{"vault_dir": "<path>", "projects": {"<repo folder>": "<project folder>"}}` (JSON, backslashes escaped).
5. Run `$PY find <a word from a note title>` to confirm, and tell the user the hooks pick it up from the next session.

**Local conventions:** if `~/.claude/claude-kit/vault.md` exists, read it first. It holds this machine's projects,
note prefixes, status-note names and any extra rules, and it overrides the defaults below.

## Recall (cheapest path first)

1. Check context: the SessionStart index (one line per note) and any "Possibly relevant vault sections" pointers
   from the prompt hook may already name the section.
2. `$PY find <specific words>`: ranked pointers `[[Note]] › Heading (Lx-y, ~N tok)`, no content. Use domain words
   and IDs (ticket IDs, hostnames, table names); drop filler. `-p "<project folder>"` to scope.
3. `$PY get "<Note>" "<heading words>"`: prints just that section (plus its subsections). Pick the smallest
   section that answers. `get "<Note>"` with no heading prints the outline with line ranges and token sizes.
4. Only if a section is cut mid-table, `Read` the note with `offset`/`limit` from the pointer's line range.
5. Broad questions spanning many notes: delegate to the `vault-scout` agent so the reading stays out of the main
   context.

Treat vault facts as dated records: they say when they were observed. For live state (cloud, git, DBs), verify
before acting, and say when the vault and reality disagree.

## Capture (when something changes)

Record a fact when a decision is made, a deploy/change lands, a finding/incident is confirmed or closed, or the
status of an open item changes. Write it **once, in the most specific note** (find it with `find`):

- Small fact: `$PY log "<Note>" "<one line: what changed, evidence>"` → dated line under `## Updates`, bumps `updated`.
- Fact that corrects or replaces existing text: `get` the section, then `Edit` that exact text, and bump the
  `updated:` property. Don't append a contradiction next to stale text.
- New topic: a new note in the project folder (`Projects/<project>/`), named like its neighbours, with frontmatter
  `type, project, area, status, updated, tags`, a `> [!summary]` first line, and a link from the project's hub note.
- Ask before large rewrites; tell the user in one line what was recorded where.

## Rules

- **No secrets ever**: names of secrets/vars only, never values. Vaults are often synced to cloud storage.
- Don't add new projects to the vault unasked.
- Obsidian syntax: wikilinks `[[Note]]`, callouts `> [!warning]`.
- The script caches an index in `~/.claude/claude-kit/` and refreshes only changed notes; nothing to maintain.
