# ADR 001: Flow-Matching Trajectory Chunking (25 Hz Producer to 500 Hz Spine)

- **Status**: Validated · **Date**: 2026-10-30
- **Feature**: [`horizon-lease-tla-scaffold`](../features/horizon-lease-tla-scaffold/brief.md), [`remaining-phases-roadmap`](../features/remaining-phases-roadmap/brief.md) · **Supersedes**: none · **Superseded by**: none

## Context
Vision-Language-Action (VLA) Flow-Matching inference executes asynchronously on GPU accelerators at `20–25 Hz` (`40–50 ms` period) with non-deterministic tail latency, whereas quadruped locomotion stability and physical collision avoidance require a deterministic `500 Hz` (`2,000,000 ns` period, `< 50 µs` jitter) control loop (`RT-05`). Directly coupling the actuator loop to the Python proposer would violate real-time WCET bounds and risk physical collisions during inference stalls.

## Options
| Option | Summary | WCET / Jitter | Memory / Cache Layout | Failure Mode | Reversibility | Verdict |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| A | **Bounded-TTL Action Chunks over Shared Memory** (`proposer/` writes chunk + integer tick TTL `shm_chunk_ttl`; `vrka-rt` steps through cached horizon at 500 Hz) | `< 2 ms` per tick; zero blocking on proposer | Fixed-size `#[repr(C, align(64))]` chunk slot in `vrka-abi` | Deterministic decay: `NOMINAL` (`ttl > 1`) → `DECEL_FALLBACK` (`ttl = 1`) → `STANCE_LOCK` (`ttl = 0`, `ctrl_vel = 0`) | High | **Selected** |
| B | Synchronous RPC / socket request per 500 Hz tick | Unbounded (`> 40 ms` GPU inference tail) | Heap-allocated IPC buffers | Missed 500 Hz deadlines; unshielded coasting on stall | Low | Rejected: violates `RT-02`, `RT-05` |

## Decision
The Python VLA proposer (`vrka_proposer`, nominal `PROPOSER_NOMINAL_HZ = 25`) generates finite-horizon trajectory chunks paired with an explicit integer tick lease (`shm_chunk_ttl \in 1..MAX_HORIZON_TTL`, measured in 500 Hz ticks) and a threat epoch (`shm_threat_epoch`). On each 500 Hz tick (`Vrka_RT_Spine_500Hz`), `vrka-rt` either ingests a fresh committed chunk (`ctrl_ttl := shm_chunk_ttl`) or decrements its cached `ctrl_ttl` by `1` tick, transitioning through `"NOMINAL"` (`ttl > 1`), `"DECEL_FALLBACK"` (`ttl = 1`, stepping velocity down toward zero), and `"STANCE_LOCK"` (`ttl = 0`, forcing `ctrl_vel = 0`).

## Invariants
| Rule | How enforced | Where |
| :-- | :-- | :-- |
| RT-04 | Expired or invalid chunk TTL deterministically transitions `NOMINAL` → `DECEL_FALLBACK` → `STANCE_LOCK` (`ctrl_vel = 0`) | [`specs/horizon_lease/vrka_horizon_lease.tla`](../../specs/horizon_lease/vrka_horizon_lease.tla), `crates/vrka-rt` |
| RT-07 | Every proposed chunk carries an integer tick lease `shm_chunk_ttl \in 1..MAX_HORIZON_TTL` decremented each 500 Hz tick | [`specs/horizon_lease/vrka_horizon_lease.tla`](../../specs/horizon_lease/vrka_horizon_lease.tla), `crates/vrka-abi` |
| RT-08 | Tick TTLs and epochs are unsigned integers (`u16`/`u32`/`u64`); all float trajectory setpoints checked with `.is_finite()` | `crates/vrka-abi`, `proposer/src/vrka_proposer` |

## Hazard, Timing & Failure Model
| Hazard / Failure Mode | Physical / Timing Impact | Mitigation / Safe-State Transition | Verification (`S-xx` / TLC) |
| :-- | :-- | :-- | :-- |
| Python VLA proposer stalls, crashes, or experiences GPU GC pause (`> 40 ms`) | No new chunks arrive across multiple 500 Hz ticks | Cached `ctrl_ttl` counts down (`3 → 2 → 1 → 0`), decelerating in `DECEL_FALLBACK` at `ctrl_ttl = 1` and locking stance (`ctrl_vel = 0`) at `ctrl_ttl = 0` while satisfying `CBFBarrierInvariant` | `make tla-check` (`SafetyNoCollision`, `CBFBarrierInvariant`), `[S-01]`, `[S-04]` |
| Proposer emitschunk with `shm_chunk_ttl = 1` near obstacle | Insufficient horizon for multi-tick nominal cruise | Immediate entry into `DECEL_FALLBACK` (`v_cand = max(shm_cmd_vel - 1, 0)`) clamped by CBF shield | [`vrka_horizon_lease.tla`](../../specs/horizon_lease/vrka_horizon_lease.tla) lines 67–80 |

## Consequences
- **+** Complete temporal isolation between 25 Hz Python ML inference and the 500 Hz Rust safety spine.
- **−** Requires pre-allocated fixed-horizon slot sizing in `vrka-abi` · **Mitigation**: compile-time `assert_cache_line_aligned!` checks (`RT-03`).

## Contracts
- [`specs/horizon_lease/vrka_horizon_lease.tla`](../../specs/horizon_lease/vrka_horizon_lease.tla) · [`proposer/src/vrka_proposer/__init__.py`](../../proposer/src/vrka_proposer/__init__.py) · [`crates/vrka-abi/src/lib.rs`](../../crates/vrka-abi/src/lib.rs)
