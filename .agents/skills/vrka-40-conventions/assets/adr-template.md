# ADR-{YYYYMMDD}-{decision-slug}: {Title}

- **Status**: {Proposed|Accepted|Validated|Superseded|Deprecated} · **Date**: {YYYY-MM-DD}
- **Feature**: [{slug}](../features/{slug}/brief.md) · **Supersedes**: {none | ADR-…} · **Superseded by**: {none}

## Context
{≤6 lines: physical safety, 500 Hz timing, `#![no_std]` constraints, and which brief decisions (`D-xx`) and Law 1 specs bind this choice.}

## Options
| Option | Summary | WCET / Jitter | Memory / Cache Layout | Failure Mode | Reversibility | Verdict |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| A | {…} | {…} | {…} | {…} | {…} | Selected |
| B | {…} | {…} | {…} | {…} | {…} | Rejected: {reason} |

## Decision
{Unambiguous statement: owning crate, `#[repr(C, align(64))]` layout, memory ordering / synchronization protocol, and degradation path.}

## Invariants
| Rule | How enforced | Where |
| :-- | :-- | :-- |
| RT-02 | {e.g. `#![no_std]` + `CountingAllocator` test proves 0 heap allocs} | `crates/…/tests/zero_alloc_*.rs` |
| RT-03 | {e.g. `assert_cache_line_aligned!(SlotHeader, 64)`} | `crates/…/src/lib.rs` |
| RT-04 | {e.g. `ctrl_ttl == 0` forces `STANCE_LOCK` (`ctrl_vel = 0`)} | `crates/vrka-rt/src/…` |

## Hazard, Timing & Failure Model <!-- required when law1: true, hotpath: true, abi: true, or tier L -->
| Hazard / Failure Mode | Physical / Timing Impact | Mitigation / Safe-State Transition | Verification (`S-xx` / TLC) |
| :-- | :-- | :-- | :-- |
| {Torn Seqlock read or stalled 20 Hz proposer} | {Stale velocity command near obstacle} | {Odd `shm_seq` rejected; `ctrl_ttl` decays `NOMINAL` → `DECEL_FALLBACK` → `STANCE_LOCK`} | `[S-02]`, `SeqlockNoTornRead` |

## ABI Compatibility & Rollback <!-- required when abi: true or cross-process wire/SHM layout changes -->
- **Layout & Alignment**: {64-byte cache-line multiples, explicit reserved fields, endianness}
- **Version / Epoch Gating**: {how mismatched producer/consumer versions fail closed prior to entering 500 Hz loop}
- **Rollback**: {revert path and shared-memory segment cleanup}

## Consequences
- **+** {benefit} · **−** {cost / static arena footprint} · **Mitigation**: {eBPF jitter monitor or follow-up}

## Contracts
- [`crates/…/src/lib.rs`](../../crates/…/src/lib.rs) · [`crates/…/tests/…`](../../crates/…/tests/…) · [`specs/…`](../../specs/…)
