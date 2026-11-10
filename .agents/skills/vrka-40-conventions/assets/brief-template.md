# Brief: {Title}

- **Slug**: `{slug}` · **Tier**: {S|M|L} · **Law1**: {true|false} · **HotPath**: {true|false} · **ABI**: {true|false} · **Type**: {feature|bugfix|refactor}
- **Status**: {Draft|Approved|Validated} · **Created**: {YYYY-MM-DD}
- **ADRs**: {none | [ADR-YYYYMMDD-x](../../adr/ADR-YYYYMMDD-x.md)}
- **Tier evidence**: {one line: which 40§1 signals decided the tier}

## Problem
{≤5 lines grounded in current code paths, e.g. `crates/vrka-shm/src/lib.rs` defines `ShmRegionDescriptor` but lacks the cache-line-aligned Seqlock header.}

## Scope
- **In**: {capability}
- **Out**: {explicit non-goal}

## Law 1 Human Specification <!-- mandatory when Law1: true; write "N/A (law1: false)" otherwise -->
- **Approved by**: {Human Architect | N/A}
- **Memory Ordering (`Ordering::*`)**: {exact load/store ordering per atomic variable, or N/A}
- **Formal TLA+ / PlusCal (`specs/`)**: {exact state variables, transitions, and safety/liveness invariants, or N/A}
- **CBF-QP Barrier Math (`vrka-cbf`)**: {exact $h(x)$, $L_f h$, $L_g h$, class-$\mathcal{K}$ $\alpha(h)$, and QP bounds, or N/A}

## Decisions
| ID | Dilemma | Chosen | Why / trade-off accepted |
| :-- | :--- | :--- | :--- |
| D-01 | {e.g. Seqlock torn-read recovery} | {Fallback to cached horizon if `ctrl_ttl > 1`, else `STANCE_LOCK`} | {Zero blocking on 500 Hz spine; bounded 1-tick latency} |
| D-02 | {⚠️ ASSUMPTION — non-Law-1 dilemma skipped} | {Conservative fail-safe `STANCE_LOCK` choice} | {Preserves physical safety invariant RT-04} |

## Scenarios
```gherkin
@S-01
Scenario: {nominal deterministic execution path}
  Given {precondition, e.g. pre-allocated aligned slot and valid horizon TTL}
  When {500 Hz tick or proposer write executes}
  Then {observable deterministic outcome with 0 heap allocations}

@S-02
Scenario: {fail-safe degradation / boundary rejection path}
  Given {stale TTL / torn Seqlock read / NaN input / unaligned buffer}
  When {action executes}
  Then {explicit typed error or transition to DECEL_FALLBACK / STANCE_LOCK}
  And {zero panics, zero heap allocations, and black-box event recorded}
```
<!-- bugfix: S-01 reproduces the defect. hotpath: cover zero-alloc (CountingAllocator), WCET/non-blocking, TTL expiry (NOMINAL -> DECEL_FALLBACK -> STANCE_LOCK), and NaN/Inf rejection. abi: cover 64-byte alignment, size assertion, and torn-read rejection. -->

## Blast Radius
| Kind | Items |
| :-- | :-- |
| Crates / Packages | {e.g. `crates/vrka-abi`, `crates/vrka-shm`, `proposer/`} |
| ABI / Wire Structs | {`#[repr(C, align(64))]` struct names or none} |
| Formal Specs | {`specs/horizon_lease/vrka_horizon_lease.tla` or none} |
| Feature Flag | {Cargo feature / config flag or none} |

## Real-Time & Safety Telemetry (M/L)
- {ring-buffer event / eBPF probe / counter names; WCET & jitter budget}
