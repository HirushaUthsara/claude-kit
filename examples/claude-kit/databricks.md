# Databricks: this machine's environments and workflows

## Environments

| Env | Workspace host | CLI profile | What lives there |
|---|---|---|---|
| dev | `adb-1111111111111111.1.azuredatabricks.net` | `myproj-dev` | pipeline dev target, job `123` |
| uat | `adb-2222222222222222.2.azuredatabricks.net` | `myproj-uat` | uat target |
| prod | `adb-3333333333333333.3.azuredatabricks.net` | `myproj-prod` | prod target, deployed by hand |

## CLI on this machine

- Installed in WSL only (run `.sh` files via `wsl -e bash /mnt/c/...`), version >= 0.230.
- Bundle repo: `/mnt/c/Users/you/projects/my-data-pipeline`.

## Workflows

- Deploy: `make deploy TARGET=<env>` (DDL first, then bundle deploy). Runbook: vault `Pipeline - Runbooks` §3.
- Batch history table: `<catalog>.output.batch_registry`.
