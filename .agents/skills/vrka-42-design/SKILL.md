---
name: vrka-42-design
description: "Vrka 40-series design step for tier M/L. Writes ADRs only for real architectural decisions (with Hazard, Timing & Failure Model and ABI Compatibility sections), then emits executable contracts on the feature branch: #[repr(C, align(64))] ABI types with compile-time assertions, panic-free compile-safe stubs, and locked #[ignore = \"vrka-contract\"] contract tests."
argument-hint: "Feature slug"
---

# Vrka 42 — Design & Contracts

Read [vrka-40-conventions](../vrka-40-conventions/SKILL.md) once if it is not already in context. Tier S never runs this skill.

## 1. Setup
1. Load `docs/features/{slug}/brief.md`. **L** requires `Status: Approved` (and a completed **Law 1 Human Specification** section if `law1: true`); **M** accepts `Draft` (approved at the 43 gate).
2. Check out `feat/{slug}`, creating it from the default branch if needed. Create `state.json` from [state-template.json](../vrka-40-conventions/assets/state-template.json) with `phase: "design"`, `law1`, `law1_human_spec`, `hotpath`, `abi`, and `base_sha` = the merge-base with the default branch.

## 2. ADR Test — only for real decisions
A decision gets an ADR only if it is (a) hard to reverse, (b) crosses a crate/process/FFI boundary or changes shared-memory/wire ABI layout, or (c) has ≥2 viable options with real WCET, memory, or safety trade-offs. Anything else is a `D-xx` row in the brief. One ADR per qualifying decision; zero is a valid outcome.
If a decision overturns an existing ADR, write a new ADR with `Supersedes:` set and mark the old one `Superseded` in both the ADR and `INDEX.md`.

## 3. Options → ADR
For each qualifying decision, list only genuinely viable options (2–3, no straw men), compared on WCET/jitter, static memory/cache-line layout, failure mode (`NOMINAL` → `DECEL_FALLBACK` → `STANCE_LOCK`), blast radius, and reversibility, checked against the brief's `D-xx` and Law 1 specification.
- **L**: `[STOP — Choice]` (gate primitive 40§5): `(Recommended)` first, plus a hybrid/custom freeform option. Write the ADR as `Accepted`.
- **M**: write the ADR as `Proposed` with the recommended option; the 43 gate accepts or redirects it.
- Use [adr-template.md](../vrka-40-conventions/assets/adr-template.md), ≤80 lines. *Hazard, Timing & Failure Model* is mandatory when `law1: true`, `hotpath: true`, `abi: true`, or tier L; *ABI Compatibility & Rollback* is mandatory when `abi: true`.
- Create or update `docs/adr/INDEX.md` from [adr-index-template.md](../vrka-40-conventions/assets/adr-index-template.md), and set the brief's `ADRs` field.

## 4. Contracts as Code
1. **ABI Layouts & Types (`RT-02`, `RT-03`, `RT-08`)**:
   - Define `#[repr(C, align(64))]` structs with explicit reserved padding and immediately invoke `vrka_abi::assert_cache_line_aligned!(StructName, EXPECTED_BYTES)` (or `const _: () = assert!(...)` for non-64-byte C-FFI types).
   - Define `#![no_std]` error/status enums (`#[derive(Clone, Copy, Debug, PartialEq, Eq)]`) and strict boundary validator signatures (`RT-08`: reject `NaN`, `Inf`, zero/expired TTLs, unaligned capacities).
   - For Python (`proposer/`), define `@dataclass(frozen=True, slots=True)` or strict Pydantic/validator contracts with full type annotations.
2. **Formal Specs (`specs/`, only when `law1: true` and human-specified)**:
   - Apply the human's verbatim PlusCal/TLA+ specification in `specs/<domain>/<spec>.tla` and `.cfg` and verify immediately via `./scripts/verify_specs.sh`. Never invent TLA+ transitions or invariants (`RT-01`).
3. **Compile-Safe Seam (`RT-05`)**:
   - Create every symbol, module, and function signature the locked contract tests import.
   - **CRITICAL (`RT-05` / Clippy `deny`)**: Workspace lints forbid `todo!()`, `unimplemented!()`, `panic!()`, `unwrap()`, and `expect()`. Stub implementations in production crates must return an explicit typed stub/error result (e.g. `Err(VrkaError::NotImplemented)` or `ShieldStatus::UninitializedStub`) so the workspace compiles cleanly under `cargo clippy --workspace --all-targets -- -D warnings` while contract tests fail when unskipped.
4. **Contract Tests (Locked)**:
   - Write at least one contract test per scenario, tagged per 40§3 (`fn test_S01_...` in Rust; `def test_S01_...` in Python), with real assertions and negative/boundary cases.
   - When `hotpath: true`, include a `CountingAllocator` harness (modeled on `crates/vrka-abi/tests/zero_alloc_hot_path.rs`) asserting `allocs == 0` and `bytes == 0`.
   - Skip each contract test with **exactly** `#[ignore = "vrka-contract"]` (Rust) or `@pytest.mark.skip(reason="vrka-contract")` (Python) per 40§7. Later task subagents may only remove that skip line.
5. **Verify**:
   - `make validate` (which runs `fmt`, `clippy -D warnings`, `check_no_std.sh`, `cargo test --workspace`, and `verify_specs.sh`) and `make check-python` (if `proposer/` changed) must be green, with contract tests reporting as `ignored` / `skipped`.
   - Run `bash <vrka-40 dir>/scripts/vrka-check.sh scan {base_sha}` (adding `--law1-approved` if `law1: true` with human spec). It must report `0 BLOCK`. Make at most 3 fix attempts, then escalate (`[STOP — Approval]` with the root cause).
6. **Commit** (40§11): `git add -- <contract tests> <seam files> <specs if any> docs/adr/ docs/features/{slug}/brief.md`, then `git commit -m "feat({slug}): design contracts"`. Set `state.json.contracts = {sha: <that commit>, locked: [contract test files]}`; `state.json` is committed with the plan in 43.

## 5. Handoff
- **M**: continue **in this session** with [vrka-43-plan](../vrka-43-plan/SKILL.md) (single combined gate).
- **L**: hand off `/vrka-43-plan {slug}`.
