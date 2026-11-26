# Log triage: this machine's apps, stores and traps

Apps: My Product API (Container App), web frontend (App Service), nightly pipeline (Databricks).

- Subscriptions: prod `00000000-1111-...`, uat `00000000-2222-...`.
- Infra store: `~/.claude/projects/<project>/memory/infra/` (`INFRA.md`, `HAZARDS.md`).
- Log Analytics: prod workspace `my-prod-logs` (id `...`). UAT console logs are not shipped: use `az containerapp logs show`.
- Timezone for timelines: Europe/London.
- Traps: <things that fooled you before>.
