# claude-kit: maintaining this repo

A public plugin marketplace (`.claude-plugin/marketplace.json`) with three plugins under `plugins/`:
`vault-memory`, `infra-ops`, `toolbox`. Each plugin has `.claude-plugin/plugin.json` and any of `skills/<name>/SKILL.md`,
`agents/<name>.md`, `hooks/hooks.json`.

## Rules

- **Method, not facts.** Skills hold how to do something. Anything specific to one user (paths, resource names,
  IDs, hosts, org/project names, URLs) lives in `~/.claude/claude-kit/<file>`, which the skill reads at run time and
  offers to create on first use. Never commit personal names, emails, local paths, secrets, subscription/tenant/
  workspace IDs, internal hostnames or company names. Examples use placeholders (`contoso`, `00000000-...`).
- **Self-contained skills.** Everything a skill uses sits in its own folder (`scripts/`, `references/`, `assets/`),
  referenced via `${CLAUDE_SKILL_DIR}` so the folder also works when copied by `npx skills add`.
- **Skill format.** Frontmatter `name` equals the folder name (lowercase, hyphens); `description` says what it does
  and when to use it, third person, under 1,024 characters. Keep `SKILL.md` under 500 lines; move detail into
  reference files one level deep.
- **Hooks** run through `hooks/py.sh` (picks `python3` or `python`) with `${CLAUDE_PLUGIN_ROOT}` paths, stdlib-only
  Python 3.10+, and must exit 0 on internal errors (exit 2 blocks the user).
- **No `version` in `plugin.json`**: every commit is a new version.
- Adding, removing or renaming a skill or agent: update the README's Reference section and the plugin description.

## Before committing

```
python3 -I -S plugins/infra-ops/hooks/guard.py selftest
python3 -I -S plugins/vault-memory/skills/vault/scripts/vault.py selftest
```

(`python` instead of `python3` on Windows.) A guard rule change needs a new case in `CASES` in `guard_rules.py`.
Read the staged diff for anything personal or company-specific (see Rules). GitHub Actions runs the self-tests on
Windows, macOS and Linux and `claude plugin validate` on every push.

## Commits

Small and focused, imperative subject, body says why. Push to `main`.
