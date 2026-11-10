---
name: vrka-44-run
description: "Vrka 40-series orchestrator. Executes an approved tasks.yaml by dispatching each task to a fresh subagent with a minimal context packet, runs independent tasks in parallel git worktrees, enforces Law 1/2/3, Red-Green, contract-lock, and invariant-scan gates, checkpoints to state.json for resumability, and escalates immediately on Law 1 gaps or real failures."
argument-hint: "Feature slug [interactive]"
---

# Vrka 44 — Run

Read [vrka-40-conventions](../vrka-40-conventions/SKILL.md) once if it is not already in context. As orchestrator, keep `tasks.yaml` and `state.json` in context. At preflight, read the brief's **Scenarios** and **Law 1 Human Specification** sections and each listed ADR's **Invariants** section once — they are the only planning text that goes into packets. Do not read source files except to resolve a merge conflict.

## 1. Preflight
1. `tasks.yaml` `status` must be `Approved` or `Running`, and the current branch `feat/{slug}`. The working tree must be clean per 40§11 (only this feature's `tasks.yaml` and `state.json` may be dirty); otherwise stop and report.
2. **Resume**: for each task with `state.tasks[id].status == running`, look for its commit on `feat/{slug}` (or on `vrka/{slug}/{id}`). If found, re-verify it and mark it `done`; otherwise remove its worktree and branch and reset the task to `pending`, keeping `attempts`. Seed `pending` for any task in `tasks.yaml` that is missing from `state.tasks`.
3. **Baseline** (once, if `state.baseline.status` is null): run `commands.validate` (`make validate`) and record pass/fail plus failing test IDs as `known_failures`. Later verdicts ignore only these; any other failure belongs to this feature.
4. Set `tasks.yaml` `status: Running` and `state.phase: "run"`.

## 2. Schedule Loop — repeat until no task is `pending`
1. **Ready set**: `pending` tasks whose `deps` are all `done`. **Batch**: up to 3 ready tasks whose `files` are pairwise disjoint and none `serial: true`; otherwise a batch of 1.
2. **Workspace**: for a batch of 1, the subagent works on `feat/{slug}`. For a batch >1: `mkdir -p ../.vrka-wt`, then `git worktree add ../.vrka-wt/{slug}-{id} -b vrka/{slug}/{id}` per task.
3. **Packet**: record `state.tasks[id].base` = the commit the task starts from (`feat/{slug}` `HEAD`). Fill [task-packet.md](../vrka-40-conventions/assets/task-packet.md) with only that task's YAML, the brief's **Law 1 Human Specification** block, its mapped scenarios' Gherkin, the one-line text of its `rules` copied from the guide's Rule Index (40§4; always include `RT-01`, `RT-09`, `RT-14`), its `read` paths, `commands`, `task_base`, `law1_flag` (`--law1-approved` only if `state.law1 == true` and `state.law1_human_spec` is populated), `contracts.sha` + `locked`, and the absolute `vrka-check.sh` path.
4. **Dispatch**: set the task to `running` and write `state.json`, then launch one `self` subagent per task (model chosen by `effort` per 40§8).
5. **Collect** each subagent's JSON result:
   - **done** — from a worktree, `git cherry-pick <commit>` onto `feat/{slug}` in task-ID order, re-run the task's `verify` there, then `git worktree remove ../.vrka-wt/{slug}-{id}` and `git branch -D vrka/{slug}/{id}`. On a cherry-pick conflict, run `git cherry-pick --abort` and reset the task to `pending` with `serial: true` for this run; this does not count as an attempt. Record `commit`, `extra_files`, and `red`.
   - **`T-00` done** — re-run `vrka-check.sh cmds` over `deferred_cmds`. Any still missing → escalate.
   - **failed / blocked** — record `note` in `state.escalations`, then `[STOP — Approval]` (40§5) with the root cause in ≤5 lines. If blocked on a **Law 1 (`RT-01`)** specification gap, ask the human architect for the exact `Ordering::*`, TLA+ predicate, or CBF equation and record it in `brief.md` and `state.law1_human_spec`. Options: **Retry with guidance (Recommended)** / **Amend plan** (re-run 43; amend via 42 when a contract or ADR is wrong, producing a new `contracts.sha`) / **Abort**.
6. Write `state.json` after every result; it is the resume point.

## 3. Slice Checkpoints
When every task in a slice is `done`, run `commands.test` (`make test`) and `commands.lint` (`make lint`) on `feat/{slug}`. A new failure (not in `known_failures`) becomes an `R-xx` task (appended to `tasks.yaml`, seeded `pending` in state) and is scheduled immediately; a second failure of the same check escalates. Checkpoint (40§11): `git add -- docs/features/{slug}/tasks.yaml docs/features/{slug}/state.json`, then `git commit -m "chore({slug}): slice {SL-x} done"`.
In `interactive` mode, add `[STOP — Verification]`: **Continue (Recommended)** / **Inspect diff** / **Amend plan**.

## 4. Completion
1. Run `commands.validate` (`make validate`), `vrka-check.sh scan {base_sha}` (with `--law1-approved` if `state.law1 == true` and one `--waive {rule}:{path}[:{line}]` per `state.waivers` entry, 40§6), and — when files are locked — `vrka-check.sh lock {contracts.sha} {locked…}`.
2. **Scan BLOCK**:
   - Non-waivable BLOCK (`LAW1_*`, `NO_STD_VIOLATION`, `HOTPATH_ALLOC`, `ABI_MISSING_ASSERT`, `PANIC_HOTPATH`, `UNDOC_UNSAFE`) → schedule an `R-xx` remediation task (one round); if it persists, escalate (`[STOP — Approval]`: **Fix with guidance (Recommended)** / **Abort** — never waive).
   - Waivable BLOCK → schedule an `R-xx` task (one round); if it persists, gate per finding: **Fix with guidance (Recommended)** / **Waive** (append `{rule, path, line, reason, approved_by, date}` to `state.waivers` from the human's answer, 40§7).
   - **Lock failure** → never waivable (40§7). Gate: **Restore unauthorized edits (Recommended)** / **Amend contract via 42**.
3. Remove leftover worktrees and `vrka/{slug}/*` branches. **Normal run**: set `tasks.yaml` `status: Done` and `state.phase: "audit"`. **Remediation mode**: restore the phase per 40§8 instead. Commit (40§11): `git add -- docs/features/{slug}/tasks.yaml docs/features/{slug}/state.json`, then `git commit -m "chore({slug}): run complete"`.
4. **Normal run**: continue **in this session** with [vrka-45-audit-and-ship](../vrka-45-audit-and-ship/SKILL.md) (in `interactive` mode, hand off `/vrka-45-audit-and-ship {slug}` instead).
   **Remediation mode** (invoked by 45, 40§8): skip the 45 handoff and return control to 45 at the step that invoked it.

## Without Subagents
Run each packet sequentially in this session as if it were the whole prompt. After each task, keep only its JSON result; do not re-open files from completed tasks. Set `state.isolation: "in-session"`.
