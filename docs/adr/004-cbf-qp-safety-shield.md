# ADR 004: Control Barrier Function (CBF-QP) Safety Shield (`vrka-cbf`)

- **Status**: Validated (Phase 1 Formal Spec) / Accepted (Phase 3 Rust Implementation) · **Date**: 2026-10-30
- **Feature**: [`horizon-lease-tla-scaffold`](../features/horizon-lease-tla-scaffold/brief.md), [`remaining-phases-roadmap`](../features/remaining-phases-roadmap/brief.md) · **Supersedes**: none · **Superseded by**: none

## Context
Proposed velocities from the 25 Hz VLA model (`shm_cmd_vel`) or cached horizon (`ctrl_vel`) can violate physical stopping-distance constraints when approaching a static boundary (`THREAT_POS`) or a dynamically tightening peer obstacle (`peer_pos`). The 500 Hz spine requires a `#![no_std]`, zero-allocation safety filter (`vrka-cbf`) that guarantees forward invariance of the collision-free set on every single tick (`RT-01`, `RT-02`, `RT-04`, `RT-08`).

## Options
| Option | Summary | WCET / Jitter | Memory / Cache Layout | Failure Mode | Reversibility | Verdict |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| A | **Forward-Invariant Braking-Distance Barrier Shield + 3-Mode Horizon Decay (`NOMINAL` → `DECEL_FALLBACK` → `STANCE_LOCK`)** | Bounded deterministic evaluation (`< 100 µs`); `0` heap allocs | `#![no_std]` stack/static workspace (`vrka-cbf`) | Clamp to maximal safe velocity $v_{\text{safe}} \in [0, v_{\text{cand}}]$; `v = 0` always feasible by induction; `STANCE_LOCK` forces `ctrl_vel = 0` | High | **Selected** |
| B | Unshielded tracking with emergency stop only when `robot_pos >= EffectiveObstaclePos` | `< 1 µs` | Minimal | Collision unavoidable when `BrakingDistance(ctrl_vel) > EffectiveObstaclePos - robot_pos` | Low | Rejected: violates `SafetyNoCollision` (`RT-04`) |
| C | Unbounded-iteration heap-allocated QP solver on the 500 Hz loop | Unbounded WCET; page-fault & allocator jitter | Heap matrices | Violates Law 2 (`RT-02`) and `50 µs` jitter budget | Low | Rejected: violates `RT-02`, `RT-05`, `RT-08` |

## Decision
Implement the Phase 1 TLA+-verified discrete Control Barrier Function safety filter (`specs/horizon_lease/vrka_horizon_lease.tla`) as the authoritative reference for `crates/vrka-cbf` and `crates/vrka-rt`:
1. **Braking-Distance Barrier Formulation (`Law 1` Verified in TLA+)**:
   - Discrete stopping distance at velocity $v \in 0..\text{MAX\_VEL}$ under unit deceleration per 500 Hz tick:
     $$\text{BrakingDistance}(v) \triangleq (v \times (v + 1)) \div 2$$
   - Barrier invariant (`CBFBarrierInvariant`):
     $$h(x) = \text{EffectiveObstaclePos} - (\text{robot\_pos} + \text{BrakingDistance}(\text{ctrl\_vel})) \ge 0$$
   - Forward-invariant 1-step safe velocity set for candidate command $v_{\text{cand}}$:
     $$\text{SafeVels}(v_{\text{cand}}) \triangleq \{v \in 0..v_{\text{cand}} : \text{robot\_pos} + v + \text{BrakingDistance}(v) \le \text{EffectiveObstaclePos}\}$$
   - The shield selects $v_{\text{safe}} = \max(\text{SafeVels}(v_{\text{cand}}))$, updates $\text{ctrl\_vel} := v_{\text{safe}}$, and advances $\text{robot\_pos} := \text{robot\_pos} + v_{\text{safe}}$. Because $v = 0$ yields $\text{robot\_pos} + 0 + \text{BrakingDistance}(0) = \text{robot\_pos} \le \text{EffectiveObstaclePos}$, $0 \in \text{SafeVels}$ holds in every reachable state.
2. **Candidate Velocity Selection Across Modes (`Vrka_RT_Spine_500Hz`)**:
   - **`"NOMINAL"`** (`shm_chunk_ttl > 1` on fresh read, or `ctrl_ttl > 2` on cached tick): $v_{\text{cand}} = \text{shm\_cmd\_vel}$ (fresh) or $\text{ctrl\_vel}$ (cached).
   - **`"DECEL_FALLBACK"`** (`shm_chunk_ttl = 1` on fresh read, or `ctrl_ttl = 2 \to 1` on cached tick): $v_{\text{cand}} = \max(v - 1, 0)$, enforcing active deceleration before lease expiry.
   - **`"STANCE_LOCK"`** (`ctrl_ttl <= 1` without a fresh valid read, or upon any `NaN`/`Inf` sensor/proposer fault): $\text{ctrl\_ttl} := 0$, $\text{ctrl\_mode} := \text{"STANCE\_LOCK"}$, $\text{ctrl\_vel} := 0$.
3. **Continuous 3D/Quadruped CBF-QP Extension (`Law 1` Gate)**: Any continuous Lie-derivative ($L_f h, L_g h$), class-$\mathcal{K}$ $\alpha(h)$, or C-FFI QP solver addition in `crates/vrka-cbf` is governed by Law 1 (`RT-01`) and requires explicit human mathematical specification before Phase 3 implementation.

## Invariants
| Rule | How enforced | Where |
| :-- | :-- | :-- |
| RT-01 | Discrete CBF barrier authored by human in `vrka_horizon_lease.tla`; continuous QP math in `vrka-cbf` requires human spec | [`specs/horizon_lease/vrka_horizon_lease.tla`](../../specs/horizon_lease/vrka_horizon_lease.tla), [`crates/vrka-cbf/src/lib.rs`](../../crates/vrka-cbf/src/lib.rs) |
| RT-02 | `crates/vrka-cbf` is unconditionally `#![no_std]` and verified by `check_no_std.sh` and `CountingAllocator` | [`scripts/check_no_std.sh`](../../scripts/check_no_std.sh) |
| RT-04 | Deterministic mode progression `NOMINAL` → `DECEL_FALLBACK` → `STANCE_LOCK` (`ctrl_vel = 0`) | [`specs/horizon_lease/vrka_horizon_lease.tla`](../../specs/horizon_lease/vrka_horizon_lease.tla) lines 65–106 |
| RT-08 | Reject `NaN`/`Inf` inputs; bounded solver iterations with fallback to verified braking deceleration / `STANCE_LOCK` | `crates/vrka-cbf`, `crates/vrka-rt` |

## Hazard, Timing & Failure Model
| Hazard / Failure Mode | Physical / Timing Impact | Mitigation / Safe-State Transition | Verification (`S-xx` / TLC) |
| :-- | :-- | :-- | :-- |
| VLA proposer commands `MAX_VEL` immediately adjacent to `EffectiveObstaclePos` | Unfiltered command would overshoot obstacle within braking horizon | `SafeVels` clamps `ctrl_vel` to maximal $v$ where $\text{robot\_pos} + v + \text{BrakingDistance}(v) \le \text{EffectiveObstaclePos}$ (down to `0`) | TLC invariants `CBFBarrierInvariant` & `SafetyNoCollision` (`make tla-check`), `[S-03]` |
| QP solver non-convergence or `NaN`/`Inf` floating-point input in continuous mode | Invalid actuator torque/velocity command | Reject frame immediately and clamp to verified discrete braking step or `STANCE_LOCK` (`ctrl_vel = 0`) | `[S-03]`, `[S-04]` |

## Consequences
- **+** Inductive forward invariance (`CBFBarrierInvariant` $\implies$ `SafetyNoCollision`) guarantees `0` collisions across all possible proposer velocities and lease expirations.
- **−** Discrete integer braking curve is conservative · **Mitigation**: Phase 3 continuous CBF-QP refines velocity tracking within the same forward-invariant safety envelope under Law 1 human specification.

## Contracts
- [`specs/horizon_lease/vrka_horizon_lease.tla`](../../specs/horizon_lease/vrka_horizon_lease.tla) · [`crates/vrka-cbf/src/lib.rs`](../../crates/vrka-cbf/src/lib.rs) · [`crates/vrka-rt/src/main.rs`](../../crates/vrka-rt/src/main.rs)
