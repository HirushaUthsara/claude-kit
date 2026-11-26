---
name: azure-ops
description: Change, deploy, and track Azure infrastructure against a persistent state store. Use when making Azure resource changes (network, private endpoints, NSG, WAF, Key Vault, storage, Postgres, AI services), deploying images to Container Apps or App Service, checking environment parity or configuration drift, or answering what is currently deployed. Not for general Azure discussion or cost estimates.
---

# azure-ops

Operate Azure estates from a written-down state store instead of re-querying `az` every time.
This skill holds **protocol only** — every project fact lives in that project's store, so the
same skill works unchanged across projects.

## The store

Located in the current project's auto-memory directory, under `infra/`:

```
<project memory>/infra/
  INFRA.md    # project header (envs, subs, RGs) + resource index + parity relations
  HAZARDS.md  # catastrophic-if-forgotten facts for this estate
  TARGET.md   # per-env secure target architecture + exception register
  <env>/*.md  # one file per resource group of coupled resources
  LOG.md      # append-only: decisions and deploys, newest first
```

Resolve `<project memory>` from the auto-memory path already in your context. If it is not
there, glob `~/.claude/projects/*/memory/` and match the current project directory name.
If `infra/` does not exist, run **init** below.

`INFRA.md` and `HAZARDS.md` are cheap — read both at the start of any task that touches Azure.
Everything else is read on demand: one resource file to answer one question.

## Core rules

1. **The store answers questions; `az` authorises changes.** Read the store to plan, explain,
   compare, or answer. Query `az` only to (a) verify the specific resources a change touches,
   immediately before mutating them, (b) verify the result afterwards, or (c) run an audit.
   Never re-sweep the estate to answer something the store already records.
2. **Approval gate.** Never run a state-changing command before explaining what changes, why,
   the blast radius, and how to roll it back — then waiting for the user to agree. One command
   per approval for irreversible work.
3. **Verify against Microsoft Learn before every write.** Confirm current syntax, required
   flags, and side effects for the mutating command. `az` surface drifts; recorded commands go
   stale. Reads need no doc check.
4. **Project `az` output.** Always use `--query` with an explicit projection and `-o tsv` or a
   narrow `-o json` object. Never let a bare `az ... show` dump into context — that is the
   single largest source of wasted tokens.
5. **Run `az` through the PowerShell tool, never Bash.** MSYS mangles `/subscriptions/...`
   resource IDs. Pass JSON bodies via `@file`.
6. **Update the store in the same turn as the change.** Resource file plus `LOG.md`, before
   moving on. Deferred bookkeeping is how state stores rot.
7. **Scale rigor to risk.** Reads: no ceremony. Reversible change in a non-production env:
   explain briefly, apply. Irreversible, or anything touching production network, identity,
   or data: full treatment — doc-verify, blast radius, rollback plan, explicit approval.

## State schema

Each resource file is a short block per resource. Keep it to what you would otherwise re-derive:

```markdown
# backend-aca (prod)
target:   ingress internal · MI SystemAssigned · KV refs versionless
intended: minReplicas 1 · 0.5 vCPU / 1 Gi · max 10
observed: 2026-08-18 — matches · image <tag> · rev --0000012
parity:   scaled → uat matched 2026-08-13
cmd:      az containerapp update -n <name> -g <rg> --image <tag>
verify:   revision Healthy at 100% traffic + /health returns 200
```

- `target` — the correct secure architecture for this env. Sourced from security review, VAPT
  findings, or hardening plans. Changes only by decision.
- `intended` — what you deliberately run today. May legitimately differ from `target`.
- `observed` — what `az` last reported, always dated. **Machine-owned:** only the audit workflow
  and the verification step of a change write here.
- `cmd` / `verify` — the command known to work for this resource and the proof that it worked.
  Record these the first time you derive them; never derive them twice.

## Deviation classes

| Comparison | Class | Response |
|---|---|---|
| `observed` ≠ `intended` | **drift** | Informational. Someone changed it outside this workflow. Reconcile: adopt or revert, then record. |
| `intended` ≠ `target` | **exception** | Legitimate if recorded in `TARGET.md` with reason, approver, and expiry. |
| `observed` ≠ `target`, no exception | **violation** | Escalate. Either fix, or record an exception with an expiry. |

An exception whose `expiry` has passed becomes a violation again. This is the whole enforcement
mechanism — a service opened "just for testing" cannot quietly become the architecture.

## Parity relations

Environments are usually **not** replicas. Declare a relation per dimension in `INFRA.md`:

- `mirror` — must match; divergence is a bug.
- `scaled` — same shape, different magnitude; record the mapping.
- `divergent-by-design` — deliberate, with a stated reason.
- `env-only` — exists on one side only.

Propagating a change follows the relation: `mirror` copies verbatim, `scaled` applies the
mapping, `env-only` does not propagate. For `divergent-by-design` the only question is whether
the change **invalidates the reason** the divergence was accepted.

Projects with one environment simply declare one env; parity stays dormant.

## Workflows

### init — new project, no store yet

1. Confirm scope with the user: which subscriptions, which resource groups, which environments.
2. Scaffold the five files. `HAZARDS.md` starts empty.
3. Write the project header into `INFRA.md`.
4. Offer an audit run to populate `observed` for the first time.

### change

1. Read `HAZARDS.md` and the relevant resource file. Do not query `az` yet.
2. Verify the command on Microsoft Learn.
3. Re-read live state for **only the resources this change touches** — cached state is not
   trustworthy for mutation.
4. Explain: what changes, why, blast radius, rollback, and which deviation class it resolves
   or creates. Wait for approval.
5. Apply. Verify using the resource's `verify` line.
6. Update `observed` + `LOG.md` in this turn.

### deploy

Preflight, before anything else:
- Re-read the live image and revision. Others may have deployed since the store was written.
- Capture current image tags and revision names as rollback refs into `LOG.md`.
- Confirm the image lineage is built for the target environment, not promoted from another.
- Confirm secret references resolve the way the target expects.

Then: approve → apply → verify with the recorded proof → log the result and the rollback refs.

### parity

1. Look up the relation for the dimension in question.
2. If asked "can we rehearse this change in the lower environment?", answer from the relations:
   a `divergent-by-design` or `env-only` dimension often means the rehearsal is structurally
   impossible. Say so **before** work starts, not after it fails.
3. If propagating, apply per the relation and record the result on both resource files.

### audit

Spawn the `azure-auditor` agent for a full read-only sweep. It reconciles `observed` and reports
drift and violations. Triage its findings with the user: fix, adopt, or record as an expiring
exception. Do not let it write `target`, `intended`, or `TARGET.md` — those are decisions.

## Hazards loop

Whenever a command surprises you, the wrong resource gets touched, a response payload lies about
stored state, or a change nearly breaks something — append it to `HAZARDS.md` immediately, in one
line, with the correct action. That file is the highest value-per-token content in the store.
