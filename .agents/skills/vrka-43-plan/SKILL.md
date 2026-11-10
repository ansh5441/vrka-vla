---
name: vrka-43-plan
description: "Vrka 40-series planner. Turns the brief, ADRs, and contracts into tasks.yaml: vertical slices, ≤200-line tasks with dependencies, parallel-safe file sets, Red-test mapping, effort-based model routing, and scenario→test→task traceability. Verification commands are proven to exist with vrka-check.sh before the single approval gate."
argument-hint: "Feature slug"
---

# Vrka 43 — Plan

Read [vrka-40-conventions](../vrka-40-conventions/SKILL.md) once if it is not already in context.

## 1. Setup
- Load `brief.md`, any ADRs listed in it, and `state.json` (contracts). Do not re-read anything already in context.
- **Tier S** (42 was skipped): check out `feat/{slug}` from the default branch and create `state.json` from [state-template.json](../vrka-40-conventions/assets/state-template.json) with `base_sha` = the merge-base and `contracts.locked: []`.

## 2. Decompose into `tasks.yaml`
Use [tasks-template.yaml](../vrka-40-conventions/assets/tasks-template.yaml).
- **Slices** are vertical and independently verifiable. Every slice carries its own fail-safe paths (`NOMINAL` → `DECEL_FALLBACK` → `STANCE_LOCK`), negative boundary tests (`NaN`/`Inf`, expired TTL, torn Seqlock sequence), and `CountingAllocator` zero-alloc checks (`RT-02`, `RT-04`); there is no separate "hardening" slice.
- **Task budget**: ≤200 changed lines, ≤3 primary `files`, one `verify` command. Split anything larger.
- **`red`**: `unskip [S-0x]` for contract tests (removes `#[ignore = "vrka-contract"]` or `@pytest.mark.skip(reason="vrka-contract")`), `new: <test path> [S-0x]` for tests the task writes first (tagged `fn test_S01_...` or `def test_S01_...`, 40§3), `n/a` only for non-behavioral tasks (ABI type stubs, `Makefile` targets, docs). Tier S has no contract tests, so behavioral tasks use `new:`. A bug fix's first task writes the regression test for `S-01` and must see it fail (`RT-13`).
- **Traceability**: every scenario maps to ≥1 test and ≥1 task, and every behavioral task maps to ≥1 scenario or a new test. Any orphan is a plan error — fix it before the gate.
- **Parallel safety**: `files` must list every path the task writes — including its red-test file and `lib.rs` / `Cargo.toml`. Set `serial: true` on tasks that touch shared workspace manifests (`Cargo.toml`, `Cargo.lock`) or shared contract test files. Use `read` for extra read-first paths (`crates/vrka-abi/tests/zero_alloc_hot_path.rs`, `docs/adr/ADR…#Invariants`).
- **`rules`**: cite only the applicable `RT-xx` IDs (`RT-01`, `RT-09`, and `RT-14` are always enforced). **`effort`**: `mechanical` | `standard` | `complex` (40§8; any `law1: true` task must be `complex`).
- **`commands.report` / `report_file`**: a command that runs the workspace test suite and writes test results to `report_file` so `vrka-check.sh covered` can prove scenario coverage in 45:
  - Rust workspace default: `cargo test --workspace -- --nocapture > target/vrka-test-report.log 2>&1` (with `report_file: target/vrka-test-report.log`).
  - If Python (`proposer/`) scenarios are also included: `cargo test --workspace -- --nocapture > target/vrka-test-report.log 2>&1 && (cd proposer && uv run pytest --junitxml=../target/proposer-junit.xml)`.
- **`T-00` tooling**: add it if task-level `Makefile` targets or report commands are missing. Show it at the gate; never change tooling silently.

## 3. Prove Commands (fail closed)
Run `bash <vrka-40 dir>/scripts/vrka-check.sh cmds "<cmd>" …`:
- `commands.typecheck` (`make typecheck`), `lint` (`make lint`), `test` (`make test`), and `validate` (`make validate`) **must already exist**, because 44 runs the baseline before any task.
- A task `verify` or `commands.report` that is `MISSING` is swapped for an existing equivalent (e.g. `cargo test --package vrka-abi`), or listed in `deferred_cmds` and created by `T-00` (every task using it depends on `T-00`; 44 re-proves it right after `T-00`).

## 4. `[STOP — Approval]`
Gate primitive per 40§5. The gate covers the brief + plan for **S**; the brief + ADR(s) + contracts + plan for **M**; the plan only for **L**. Show ≤15 lines:
tier + flags (`law1`, `hotpath`, `abi`) + evidence · slices → tasks (id, title, deps, verify) · critical path · parallel groups · scenario coverage · `T-00` tooling changes · proposed new dependencies (`cargo deny` impact) · ADR decisions (M).
Options: **Approve (Recommended)** / **Request changes** / **Reject**.
- **Request changes**: revise and re-gate. If an M ADR choice is redirected, rewrite that ADR (and its contracts, via the 42 procedure) before re-gating.
- **Approve**: brief → `Approved`; M ADRs → `Accepted` (update `INDEX.md`); `tasks.yaml` → `status: Approved`; seed `state.json.tasks` (all `pending`) and set `phase: "run"`. Commit (40§11): `git add -- docs/features/{slug}/brief.md docs/features/{slug}/tasks.yaml docs/features/{slug}/state.json` plus `docs/adr/` when ADRs changed, then `git commit -m "chore({slug}): approved plan"`. For tier S this is the commit that first records the brief.

## 5. Handoff
`/vrka-44-run {slug}` — autonomous by default; append `interactive` for per-slice verification gates.
