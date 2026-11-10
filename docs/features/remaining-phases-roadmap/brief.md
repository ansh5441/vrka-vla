# Brief: Remaining Phases Roadmap (Phases 2–5: ABI/Seqlock IPC, 500 Hz CBF Spine, Swarm Leases, VLA Proposer & Sim)

- **Slug**: `remaining-phases-roadmap` · **Tier**: L · **Law1**: true · **HotPath**: true · **ABI**: true · **Type**: feature
- **Status**: Validated · **Created**: 2026-11-09
- **ADRs**: [001-flow-matching-chunking](../../adr/001-flow-matching-chunking.md), [002-spatial-security-tokens](../../adr/002-spatial-security-tokens.md), [003-wait-free-seqlock-ipc](../../adr/003-wait-free-seqlock-ipc.md), [004-cbf-qp-safety-shield](../../adr/004-cbf-qp-safety-shield.md), [005-multi-agent-pack-leases](../../adr/005-multi-agent-pack-leases.md)
- **Tier evidence**: Spans Law 1 (`Ordering::*` in `vrka-shm`, CBF barrier math in `vrka-cbf`, multi-agent TLA+ in `specs/pack_swarm/`), 500 Hz `#![no_std]` hot path (`vrka-abi`, `vrka-shm`, `vrka-cbf`, `vrka-rt`, `vrka-swarm`, `vrka-ebpf`), and 64-byte cache-line / C-FFI ABI boundaries (`#[repr(C, align(64))]`, `io_uring`, `libmujoco`).

## Problem
Phase 1 formally specified and model-checked `VrkaHorizonLease` in [`specs/horizon_lease/vrka_horizon_lease.tla`](../../../specs/horizon_lease/vrka_horizon_lease.tla) (`291,528` distinct states, `0` invariant violations for `SafetyNoCollision`, `CBFBarrierInvariant`, and `SeqlockNoTornRead`). The Rust workspace crates ([`vrka-abi`](../../../crates/vrka-abi/src/lib.rs), [`vrka-shm`](../../../crates/vrka-shm/src/lib.rs), [`vrka-cbf`](../../../crates/vrka-cbf/src/lib.rs), [`vrka-rt`](../../../crates/vrka-rt/src/main.rs), [`vrka-swarm`](../../../crates/vrka-swarm/src/lib.rs), [`vrka-ebpf`](../../../crates/vrka-ebpf/src/lib.rs), [`vrka-sim`](../../../crates/vrka-sim/src/lib.rs)), [`specs/pack_swarm/`](../../../specs/pack_swarm/README.md), and the 25 Hz Python proposer ([`proposer/`](../../../proposer/src/vrka_proposer/__init__.py)) remain at their initial compile-safe stubs and must be implemented across Phases 2–5.

## Scope
- **In**:
  1. **Phase 2 — Cache-Line ABI & Wait-Free Seqlock IPC (`vrka-abi`, `vrka-shm`)**: `#[repr(C, align(64))]` `ShmSlotHeader`, `ActionChunkSlot`, `SpatialSecurityToken`, and `FlightRecorderEntry` with `assert_cache_line_aligned!`, `#![no_std]` `.is_finite()` validators, and single-writer / non-spinning multi-reader Seqlock IPC (`WriteBegin` odd `shm_seq` → `WriteCommit` even `shm_seq`) (`RT-01`..`RT-03`, `RT-06`, `RT-08`).
  2. **Phase 3 — `#![no_std]` CBF Safety Shield, 500 Hz Spine & eBPF Telemetry (`vrka-cbf`, `vrka-rt`, `vrka-ebpf`)**: Discrete braking-distance barrier filter (`BrakingDistance(v)`, `SafeVels`) and human-specified continuous CBF-QP clamp (`vrka-cbf`); 500 Hz state machine (`NOMINAL` → `DECEL_FALLBACK` → `STANCE_LOCK`), `mlockall`, `SCHED_FIFO`, injected monotonic clock, lock-free flight recorder (`vrka-rt`), and `50 µs` jitter probes (`vrka-ebpf`) (`RT-04`, `RT-05`, `RT-07`, `RT-10`, `RT-12`, `RT-19`, `RT-20`).
  3. **Phase 4 — Multi-Agent Wolf-Pack Swarm Leases (`specs/pack_swarm/`, `vrka-swarm`)**: Multi-agent pack TLA+ specification (`specs/pack_swarm/`) and non-blocking `io_uring` UDP peer lease broadcast/receive (`DEFAULT_SWARM_PORT = 9500`) updating `EffectiveObstaclePos` and `peer_lease_ttl` (`RT-01`, `RT-16`..`RT-18`).
  4. **Phase 5 — 25 Hz Python VLA Proposer & 500 Hz Chaos Simulator (`proposer/`, `vrka-sim`)**: 25 Hz Flow-Matching chunk producer (`PROPOSER_NOMINAL_HZ = 25`) and deterministic 500 Hz `libmujoco` chaos harness (`DEFAULT_SIM_HZ = 500`) (`RT-13`, `RT-15`).
- **Out**: Modifying the validated Phase 1 `specs/horizon_lease/vrka_horizon_lease.tla` state machine without a new Law 1 human directive.

## Law 1 Human Specification
- **Approved by**: Human Architect for Phase 1 TLA+ baseline ([`vrka_horizon_lease.tla`](../../../specs/horizon_lease/vrka_horizon_lease.tla)); explicit human spec required before each phase's Law 1 code:
- **Memory Ordering (`Ordering::*`) (Phase 2 `vrka-shm`)**: Exact `Ordering::Acquire` / `Ordering::Release` / `atomic::fence` sequence on `shm_seq` in `SeqlockWriter` and `SeqlockReader` (`RT-01`).
- **Formal TLA+ / PlusCal (`specs/`) (Phase 4 `specs/pack_swarm/`)**: Multi-agent tie-breaking and corridor lease arbitration invariants beyond Phase 1 `Peer_Wolf_UDP`.
- **CBF-QP Barrier Math (`vrka-cbf`) (Phase 3)**: Phase 1 discrete barrier $h(x) = \text{EffectiveObstaclePos} - (\text{robot\_pos} + \lfloor v(v+1)/2 \rfloor) \ge 0$ is human-approved; continuous Lie derivatives ($L_f h, L_g h, \alpha(h)$) require explicit human equations.

## Decisions
| ID | Dilemma | Chosen | Why / trade-off accepted |
| :-- | :--- | :--- | :--- |
| D-01 | Seqlock torn-read recovery on 500 Hz spine ([ADR 003](../../adr/003-wait-free-seqlock-ipc.md)) | Discard odd/mismatched `shm_seq` without spinning; step cached `ctrl_ttl` ladder (`>2` `NOMINAL` → `=2` `DECEL_FALLBACK` → `<=1` `STANCE_LOCK`) | Guarantees wait-free `O(1)` WCET (`< 2 ms`) and matches `Vrka_RT_Spine_500Hz` |
| D-02 | CBF shield infeasibility / fault fallback ([ADR 004](../../adr/004-cbf-qp-safety-shield.md)) | Clamp to maximal safe velocity in `SafeVels` (`0` always feasible by `CBFBarrierInvariant`); force `STANCE_LOCK` (`ctrl_vel = 0`) on `NaN`/`Inf` | Preserves `SafetyNoCollision` with zero dynamic allocation (`RT-04`, `RT-08`) |
| D-03 | Dynamic peer obstacle aggregation ([ADR 005](../../adr/005-multi-agent-pack-leases.md)) | `EffectiveObstaclePos = min(peer_pos, THREAT_POS)` while `peer_lease_ttl > 0`; decrement `peer_lease_ttl` each tick on drop | Prevents both mid-corridor collisions and permanent deadlocks after wireless drops |
| D-04 | Phased execution across Phases 2–5 | Execute each phase (`Phase 2` → `Phase 3` → `Phase 4` → `Phase 5`) as a vertical slice with locked contract tests | Keeps diffs surgical (`≤ 200` lines per file, `RT-11`) and isolates Law 1 gates |

## Scenarios
```gherkin
@S-01
Scenario: Phase 2 wait-free Seqlock round-trip and 64-byte cache-line ABI alignment with zero heap allocations
  Given 64-byte aligned `ShmSlotHeader` and `ActionChunkSlot` in `vrka-abi` and a pre-allocated `vrka-shm` slot
  When the 25 Hz writer commits a valid chunk (`shm_chunk_ttl > 1`, even `shm_seq`) and the 500 Hz reader polls it under `CountingAllocator`
  Then the reader receives the exact payload, `assert_cache_line_aligned!` holds, and `CountingAllocator` reports 0 allocations and 0 bytes

@S-02
Scenario: Phase 2 Seqlock torn-read, unaligned buffer, and NaN/Inf boundary rejection
  Given an odd `shm_seq` (`WriteBegin` in flight), mismatched `seq_before != seq_after`, unaligned region capacity, or `NaN`/`Inf` velocity
  When `vrka-shm` / `vrka-abi` validates or reads the slot
  Then the read is rejected in O(1) without spinning or panicking, returning a typed `#![no_std]` error with 0 heap allocations

@S-03
Scenario: Phase 3 CBF braking-distance shield clamps unsafe candidate velocities to preserve CBFBarrierInvariant
  Given ego state `(robot_pos, ctrl_vel)` and `EffectiveObstaclePos` in `vrka-cbf`
  When a candidate velocity `v_cand` would violate `robot_pos + v + BrakingDistance(v) <= EffectiveObstaclePos`
  Then `vrka-cbf` projects the command onto the maximal safe velocity `v_safe \in SafeVels` with 0 heap allocations

@S-04
Scenario: Phase 3 500 Hz spine deterministic horizon TTL decay ladder (NOMINAL -> DECEL_FALLBACK -> STANCE_LOCK)
  Given an active horizon lease `ctrl_ttl = 3` in `vrka-rt` and a stalled proposer (no fresh committed Seqlock frames)
  When successive 500 Hz ticks execute with an injected monotonic clock
  Then `vrka-rt` transitions `NOMINAL` (`ctrl_ttl: 3 -> 2`) -> `DECEL_FALLBACK` (`ctrl_ttl: 2 -> 1`, decelerating `ctrl_vel`) -> `STANCE_LOCK` (`ctrl_ttl = 0`, `ctrl_vel = 0`) and records binary flight-recorder events

@S-05
Scenario: Phase 4 & 5 authenticated peer lease tightening, expiry decay, and 500 Hz closed-loop chaos simulation
  Given `vrka-swarm`, `vrka_proposer` (25 Hz), and `vrka-sim` (500 Hz) running with injected proposer stalls, torn writes, and UDP drops
  When a valid authenticated peer lease arrives at `peer_pos < THREAT_POS` and later expires (`peer_lease_ttl -> 0`)
  Then `EffectiveObstaclePos` tightens to `peer_pos` and reverts to `THREAT_POS` on expiry, maintaining `SafetyNoCollision` (`robot_pos <= EffectiveObstaclePos`) across all simulated ticks
```

## Blast Radius
| Kind | Items |
| :-- | :-- |
| Crates / Packages | [`crates/vrka-abi`](../../../crates/vrka-abi/src/lib.rs), [`crates/vrka-shm`](../../../crates/vrka-shm/src/lib.rs), [`crates/vrka-cbf`](../../../crates/vrka-cbf/src/lib.rs), [`crates/vrka-rt`](../../../crates/vrka-rt/src/main.rs), [`crates/vrka-swarm`](../../../crates/vrka-swarm/src/lib.rs), [`crates/vrka-ebpf`](../../../crates/vrka-ebpf/src/lib.rs), [`crates/vrka-sim`](../../../crates/vrka-sim/src/lib.rs), [`proposer/`](../../../proposer/src/vrka_proposer/__init__.py) |
| ABI / Wire Structs | `CacheLineSlotPlaceholder`, `ShmSlotHeader`, `ActionChunkSlot`, `SpatialSecurityToken`, `PeerLeaseFrame`, `FlightRecorderEntry` (`#[repr(C, align(64))]`) |
| Formal Specs | [`specs/horizon_lease/vrka_horizon_lease.tla`](../../../specs/horizon_lease/vrka_horizon_lease.tla) (Phase 1 baseline), [`specs/pack_swarm/`](../../../specs/pack_swarm/README.md) (Phase 4) |
| Feature Flag | `vrka-shm/std` (cold-path POSIX `mmap` initialization only; default features remain `#![no_std]`) |

## Real-Time & Safety Telemetry (M/L)
- **Flight Recorder & eBPF (`RT-12`, `RT-19`)**: 64-byte `FlightRecorderEntry` on mode/clamp/expiry transitions + `vrka-ebpf` wakeup jitter probe (`MAX_JITTER_BUDGET_NS = 50_000` / `50 µs` within `2,000,000 ns` period).
