---
name: databricks-ops
description: Run, deploy and inspect Databricks work safely — asset bundles (validate, plan, deploy, run), jobs and pipeline runs (status, failure, repair, refresh), notebook import/export, Lakebase/Postgres synced tables, SQL warehouses. Use whenever a task touches the databricks CLI or a bundle, even when the user only says "deploy the job", "why did the run fail", "push this notebook", "refresh UAT" or "check the synced tables". Not for explaining Spark or Databricks concepts (answer those directly).
---

# databricks-ops

Protocol for operating Databricks safely. Environment facts and runbooks are not in this skill.

**Local facts first:** read `~/.claude/claude-kit/databricks.md` if it exists. It holds this machine's environments
(workspace host, CLI profile, what runs where), where the CLI is installed, project-specific workflows and runbook
pointers. If it doesn't exist, run `databricks auth profiles` and `databricks bundle validate -t <target>` to learn
the environments, offer to write that file, and ask the user what you can't discover.

If a command contradicts the local file, trust `databricks auth profiles` and `bundle validate -t <env>`, then
fix the file.

## How to run the CLI

- Bundle commands run from the bundle's repo directory with `-t <target>`. Non-bundle commands (`jobs`,
  `pipelines`, `api`) with a non-default profile may need to run outside the repo: inside it, the bundle's default
  host can conflict with the profile's host.
- If the CLI lives only in WSL: write the commands into a `.sh` file (LF line endings) in your scratchpad and run
  it from PowerShell with `wsl -e bash /mnt/c/<path with forward slashes>/run.sh`. Calling `wsl` from Git Bash
  rewrites `/mnt/c/...` paths.
- Set the profile explicitly in every script (`export DATABRICKS_CONFIG_PROFILE=<profile>`).
- Project every JSON response to the fields you need, inside the script (`python3 -c` if there is no `jq`).
  A raw job or run JSON is thousands of tokens.

```bash
#!/usr/bin/env bash
set -euo pipefail
export DATABRICKS_CONFIG_PROFILE=<dev profile>
cd <bundle repo>          # bundle commands only
databricks bundle validate -t dev
databricks jobs get-run 123 -o json | python3 -c 'import json,sys; r=json.load(sys.stdin); [print(t["task_key"], t["state"].get("result_state"), t.get("run_id")) for t in r.get("tasks",[])]'
```

- Never print tokens or passwords (`databricks auth token`, database role passwords).
- Read-only SQL on a warehouse: `databricks api post /api/2.0/sql/statements` with a SELECT, or a small helper
  script kept in the scratchpad, not the repo.

## Safety tiers

| Tier | Examples | Gate |
|---|---|---|
| Read | `auth profiles`, `current-user me`, `bundle validate/plan/summary`, `jobs get/get-run/list-runs/get-run-output`, `pipelines get/get-update/list-pipeline-events`, `workspace list/export/get-status`, `warehouses list`, SELECT | none |
| Dev write | `bundle deploy -t dev`, `jobs run-now`/`repair-run` in dev, `workspace import` to dev, `pipelines start-update` in dev, DDL in dev | Two-line explanation, then the user's yes. Dev output may be live for someone: say what reads it. |
| UAT/prod write | anything that changes uat or prod | Explain end to end; show `bundle plan` and call out every DELETE; state the rollback; one command per approval |

Only on the user's explicit words in this conversation: `--auto-approve`, `--force`, `bundle destroy`,
`DROP`/`TRUNCATE`/`DELETE`, cancelling a run, `--full-refresh` in uat/prod, and any change in a shared workspace
outside your own bundle paths.

## Workflows

**Deploy a bundle.** Validate → `bundle plan -t <env>` (read the deletes) → any DDL migration dry run the project
has → deploy. Verify with `bundle summary -t <env>` and whatever the project records (a migrations table, a run).

**Failed run.** `jobs get-run <run_id>` projected to tasks and states → `jobs get-run-output` for the failed task →
the project's batch/audit table if it has one. Fix by repairing only the failed task
(`jobs repair-run <run_id> --rerun-tasks <task>`, under the matching tier). If the diagnosis needs many log reads,
delegate to the `log-triage` agent.

**Notebook push.** `workspace export` the current version to the scratchpad first (rollback), then
`workspace import`, then verify with `workspace get-status`.

**Synced tables (Lakebase).** Triggered syncs apply changed rows incrementally; for very large changes a full
refresh can be quicker. Check whether `prevent_destroy` or grants are involved before changing one.

## Record

After a deploy, run, repair or config change, record one line (what, env, commit/run id, evidence) where the
project keeps its log: the `vault` skill if the vault-memory plugin is installed, otherwise the repo's changelog.
A surprise or near miss goes into the runbook's warnings. An environment fact that changed goes into
`~/.claude/claude-kit/databricks.md`.
