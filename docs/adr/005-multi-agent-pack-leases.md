# ADR 005: Multi-Agent Pack Leases & `io_uring` Broadcasts (`vrka-swarm`)

- **Status**: Validated (Phase 1 Single-Peer Formal Spec) / Accepted (Phase 4 Multi-Agent Swarm Implementation) · **Date**: 2026-10-30
- **Feature**: [`horizon-lease-tla-scaffold`](../features/horizon-lease-tla-scaffold/brief.md), [`remaining-phases-roadmap`](../features/remaining-phases-roadmap/brief.md) · **Supersedes**: none · **Superseded by**: none

## Context
In a multi-quadruped wolf pack (`vrka-swarm`), peer robots dynamically occupy shared corridors while UDP wireless links suffer packet loss, jitter, and partitions. If a peer robot steps in front of the ego robot without respecting the ego robot's current stopping horizon, or if a stale peer position is held indefinitely after packet drops, the pack will either collide or deadlock (`RT-04`, `RT-07`, `RT-17`, `RT-18`).

## Options
| Option | Summary | WCET / Jitter | Memory / Cache Layout | Failure Mode | Reversibility | Verdict |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| A | **Braking-Horizon-Guarded Peer Lease (`peer_lease_ttl`) + Non-Blocking `io_uring` UDP Broadcast** | Non-blocking CQE poll (`< 5 µs`); zero syscalls when pre-registered | Pre-allocated `#[repr(C, align(64))]` peer table & `io_uring` buffers | Dropped packets decrement `peer_lease_ttl` to `0`, reverting `EffectiveObstaclePos` to `THREAT_POS` | High | **Selected** |
| B | Blocking BSD socket `recvfrom` inside the 500 Hz loop | Unbounded kernel syscall / wakeup jitter | Kernel-to-user copy per packet | Violates `RT-05` and `50 µs` jitter budget | Low | Rejected: violates `RT-05`, `RT-18` |
| C | Unconstrained peer position updates (accept peer lease inside ego braking distance) | `O(1)` | Same | Instant violation of `CBFBarrierInvariant` before ego robot can decelerate | Low | Rejected: violates `CBFBarrierInvariant` |

## Decision
Adopt the Phase 1 TLA+-verified peer lease protocol (`Peer_Wolf_UDP` in `specs/horizon_lease/vrka_horizon_lease.tla`) and extend it to `N`-peer pack coordination in `specs/pack_swarm/` and `crates/vrka-swarm`:
1. **Effective Obstacle Aggregation (`EffectiveObstaclePos`)**:
   $$\text{EffectiveObstaclePos} \triangleq \begin{cases} \text{peer\_pos} & \text{if } \text{peer\_lease\_ttl} > 0 \land \text{peer\_pos} < \text{THREAT\_POS} \\ \text{THREAT\_POS} & \text{otherwise} \end{cases}$$
2. **Braking-Horizon Admission Guard (`PeerStep`)**:
   - A peer lease reservation is admissible only outside the ego robot's committed braking envelope:
     $$\text{peer\_pos} \in (\text{robot\_pos} + \text{BrakingDistance}(\text{ctrl\_vel}))..\text{MAX\_CORRIDOR\_POS}, \quad \text{peer\_lease\_ttl} \in 1..\text{MAX\_HORIZON\_TTL}$$
   - On network drop or absence of a fresh UDP frame, `peer_lease_ttl` decrements by `1` each step until `peer_lease_ttl = 0`, at which point the expired peer lease is released and `EffectiveObstaclePos` reverts to `THREAT_POS`.
3. **Non-Blocking `io_uring` Transport (`crates/vrka-swarm`)**:
   - Uses pre-registered `#[repr(C, align(64))]` packet buffers on `DEFAULT_SWARM_PORT = 9500`, IEEE 1588 PTPv2 monotonic timestamps (`RT-16`), and authenticated `SpatialSecurityToken` validation (`RT-17`) without blocking or retrying inside a 500 Hz tick (`RT-18`).

## Invariants
| Rule | How enforced | Where |
| :-- | :-- | :-- |
| RT-01 | `Peer_Wolf_UDP` and `EffectiveObstaclePos` formally verified in `vrka_horizon_lease.tla`; multi-agent `specs/pack_swarm/*.tla` requires human spec | [`specs/horizon_lease/vrka_horizon_lease.tla`](../../specs/horizon_lease/vrka_horizon_lease.tla), [`specs/pack_swarm/`](../../specs/pack_swarm/) |
| RT-07 | Every peer obstacle reservation carries an integer `peer_lease_ttl \in 1..MAX_HORIZON_TTL` that decays to `0` on packet loss | [`specs/horizon_lease/vrka_horizon_lease.tla`](../../specs/horizon_lease/vrka_horizon_lease.tla) lines 31–35, 110–127 |
| RT-17 | Authenticated spatial token, monotonic sequence number, and corridor bounds (`0..MAX_CORRIDOR_POS`) verified before updating `peer_pos` | `crates/vrka-swarm/src/lib.rs` |
| RT-18 | Non-blocking `io_uring` polling with pre-registered buffers; zero hot-path retries | `crates/vrka-swarm/src/lib.rs` |

## Hazard, Timing & Failure Model
| Hazard / Failure Mode | Physical / Timing Impact | Mitigation / Safe-State Transition | Verification (`S-xx` / TLC) |
| :-- | :-- | :-- | :-- |
| Peer robot appears at `peer_pos < THREAT_POS` outside ego braking distance | Tightens `EffectiveObstaclePos` mid-stride | Ego 500 Hz spine immediately clamps `ctrl_vel` via `SafeVels` against the tighter `EffectiveObstaclePos`, preserving `CBFBarrierInvariant` | TLC invariants `CBFBarrierInvariant` & `SafetyNoCollision` (`make tla-check`), `[S-05]` |
| UDP packet loss / wireless partition | Peer lease stops refreshing | `peer_lease_ttl` decrements to `0` without blocking the 500 Hz loop | [`vrka_horizon_lease.tla`](../../specs/horizon_lease/vrka_horizon_lease.tla) lines 121–125, `[S-05]` |

## ABI Compatibility & Rollback
- **Layout & Alignment**: Swarm UDP wire frames map into 64-byte cache-line-aligned pre-registered `io_uring` buffers (`assert_cache_line_aligned!`) with explicit endianness and protocol version fields.
- **Version / Epoch Gating**: Frames failing PTPv2 drift bounds, protocol version, or MAC verification are dropped at ingestion (`RT-16`, `RT-17`).
- **Rollback**: Disable peer lease ingestion (`peer_lease_ttl = 0`) so `EffectiveObstaclePos` falls back deterministically to `THREAT_POS`.

## Consequences
- **+** Proves that dynamic peer obstacle updates and arbitrary packet drops never violate `SafetyNoCollision` or `CBFBarrierInvariant`.
- **−** Requires coordinated braking-distance admission for multi-robot intersections · **Mitigation**: Phase 4 `specs/pack_swarm/` formalizes multi-agent tie-breaking under Law 1.

## Contracts
- [`specs/horizon_lease/vrka_horizon_lease.tla`](../../specs/horizon_lease/vrka_horizon_lease.tla) · [`specs/pack_swarm/README.md`](../../specs/pack_swarm/README.md) · [`crates/vrka-swarm/src/lib.rs`](../../crates/vrka-swarm/src/lib.rs)
