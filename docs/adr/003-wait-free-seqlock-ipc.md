# ADR 003: Wait-Free Seqlock Shared-Memory IPC (`vrka-shm`)

- **Status**: Validated (Phase 1 Formal Spec) / Accepted (Phase 2 Rust Implementation) · **Date**: 2026-10-30
- **Feature**: [`horizon-lease-tla-scaffold`](../features/horizon-lease-tla-scaffold/brief.md), [`remaining-phases-roadmap`](../features/remaining-phases-roadmap/brief.md) · **Supersedes**: none · **Superseded by**: none

## Context
The 25 Hz Python proposer (`VLA_Proposer_20Hz`) and the 500 Hz Rust control spine (`Vrka_RT_Spine_500Hz`) share action chunks across OS process boundaries. Mutex-based IPC risks priority inversion and unbounded blocking on the 500 Hz spine (`RT-05`). We require a wait-free single-writer / multi-reader synchronization protocol proven free of torn reads (`SeqlockNoTornRead`) and false cache-line sharing (`RT-03`, `RT-06`).

## Options
| Option | Summary | WCET / Jitter | Memory / Cache Layout | Failure Mode | Reversibility | Verdict |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| A | **Cache-Line-Aligned Wait-Free Seqlock with Immediate Cached-Horizon Fallback** (odd `shm_seq` = write in progress; reader never spins on torn read) | `O(1)` wait-free (`< 200 ns`); zero reader spinning | `#[repr(C, align(64))]` header & payload slots (`CACHE_LINE_BYTES = 64`) | Torn/odd read discarded immediately; spine falls back to cached `ctrl_ttl` decay (`NOMINAL` → `DECEL_FALLBACK` → `STANCE_LOCK`) | High | **Selected** |
| B | Spin-wait Seqlock reader (reader loops until `shm_seq` becomes even) | Unbounded if Python writer is preempted mid-write | Same 64-byte slot layout | 500 Hz deadline overrun if writer stalls while `shm_seq` is odd | Medium | Rejected: violates `RT-05`, `RT-06` |
| C | POSIX `pthread_mutex` with `PTHREAD_PRIO_INHERIT` across processes | Syscall overhead + cross-process lock contention | OS futex state | Descheduled Python process blocks 500 Hz spine | Low | Rejected: violates `RT-05` |

## Decision
Adopt the Phase 1 TLA+-verified wait-free Seqlock protocol (`specs/horizon_lease/vrka_horizon_lease.tla`):
1. **Writer (`VLA_Proposer_20Hz`)**:
   - `WriteBegin`: increments `shm_seq` to an **odd** value (`(shm_seq + 1) % 4` in bounded TLC model; monotonic `u64` in Rust) before mutating payload fields (`shm_cmd_vel`, `shm_chunk_ttl`, `shm_threat_epoch`). In the TLA+ model, `shm_cmd_vel := -1` explicitly injects an out-of-range sentinel during the odd window to prove the reader never ingests an in-flight write.
   - `WriteCommit`: writes `shm_cmd_vel \in 0..MAX_VEL`, `shm_chunk_ttl \in 1..MAX_HORIZON_TTL`, `shm_threat_epoch := (shm_seq + 1) \div 2`, and increments `shm_seq` to an **even** value.
2. **Reader (`Vrka_RT_Spine_500Hz`)**:
   - Reads `seq_before`, copies the 64-byte-aligned payload, and reads `seq_after`.
   - Accepts the frame iff `seq_before == seq_after`, `seq_before % 2 == 0`, and `shm_chunk_ttl > 0`.
   - On any odd or mismatched sequence, immediately discards the read without spinning and executes the cached `ctrl_ttl` countdown ladder (`ctrl_ttl > 2` → `NOMINAL`; `ctrl_ttl = 2` → `DECEL_FALLBACK`; `ctrl_ttl <= 1` → `STANCE_LOCK`).
3. **Law 1 Memory Ordering Boundary**: Exact Rust `core::sync::atomic::Ordering` annotations in `crates/vrka-shm` are governed by Law 1 (`RT-01`) and require explicit human specification before Phase 2 code emission.

## Invariants
| Rule | How enforced | Where |
| :-- | :-- | :-- |
| RT-01 | Formal Seqlock state machine authored by human in `vrka_horizon_lease.tla`; Rust `Ordering::*` requires explicit human spec | [`specs/horizon_lease/vrka_horizon_lease.tla`](../../specs/horizon_lease/vrka_horizon_lease.tla), `crates/vrka-shm` |
| RT-02 | `crates/vrka-abi` and default-feature `crates/vrka-shm` are `#![no_std]` with `0` heap allocations | [`scripts/check_no_std.sh`](../../scripts/check_no_std.sh), [`crates/vrka-abi/tests/zero_alloc_hot_path.rs`](../../crates/vrka-abi/tests/zero_alloc_hot_path.rs) |
| RT-03 | All shared-memory headers and slots are `#[repr(C, align(64))]` with `assert_cache_line_aligned!` | [`crates/vrka-abi/src/lib.rs`](../../crates/vrka-abi/src/lib.rs) |
| RT-06 | `SeqlockNoTornRead`: `ctrl_vel \in 0..MAX_VEL /\ ctrl_ttl \in 0..MAX_HORIZON_TTL /\ ((shm_seq % 2 = 0) => (shm_cmd_vel \in 0..MAX_VEL))` | [`specs/horizon_lease/vrka_horizon_lease.tla`](../../specs/horizon_lease/vrka_horizon_lease.tla) lines 37–40 |

## Hazard, Timing & Failure Model
| Hazard / Failure Mode | Physical / Timing Impact | Mitigation / Safe-State Transition | Verification (`S-xx` / TLC) |
| :-- | :-- | :-- | :-- |
| Writer preempted during `WriteBegin` (`shm_seq % 2 != 0`, `shm_cmd_vel = -1`) | Reader could observe torn/invalid velocity `-1` if unlocked | Reader rejects odd `shm_seq` in `O(1)` and steps cached `ctrl_ttl` toward `DECEL_FALLBACK` / `STANCE_LOCK` | TLC invariant `SeqlockNoTornRead` (`make tla-check`), `[S-02]` |
| False cache-line sharing between 25 Hz writer core and 500 Hz reader core | L1/L2 cache coherency stalls inflating 500 Hz jitter | 64-byte alignment (`CACHE_LINE_BYTES = 64`) enforced via `assert_cache_line_aligned!` | [`crates/vrka-abi/src/lib.rs`](../../crates/vrka-abi/src/lib.rs), `[S-02]` |

## ABI Compatibility & Rollback
- **Layout & Alignment**: Every shared-memory header and slot is a multiple of `64` bytes (`#[repr(C, align(64))]`) with explicit zeroed padding (`reserved: [u8; N]`) and verified region capacity (`ShmRegionDescriptor::is_aligned()`).
- **Version / Epoch Gating**: `shm_threat_epoch` advances monotonically (`(shm_seq + 1) \div 2` in TLA+); unaligned regions fail closed at cold-path setup before entering the 500 Hz loop.
- **Rollback**: Unlink the POSIX shared-memory segment and revert `vrka-shm`/`vrka-abi` together.

## Consequences
- **+** Wait-free `O(1)` reads on the 500 Hz spine; mathematically proven torn-read freedom (`SeqlockNoTornRead`) even when the writer is paused mid-write.
- **−** Single-tick torn reads consume 1 tick of cached `ctrl_ttl` · **Mitigation**: `MAX_HORIZON_TTL` spans multiple 500 Hz ticks so transient writer preemption does not trip `STANCE_LOCK`.

## Contracts
- [`specs/horizon_lease/vrka_horizon_lease.tla`](../../specs/horizon_lease/vrka_horizon_lease.tla) · [`crates/vrka-abi/src/lib.rs`](../../crates/vrka-abi/src/lib.rs) · [`crates/vrka-shm/src/lib.rs`](../../crates/vrka-shm/src/lib.rs)
