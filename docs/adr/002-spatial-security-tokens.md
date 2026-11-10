# ADR 002: Spatial Security Tokens & Capability-Bounded Envelopes

- **Status**: Accepted · **Date**: 2026-10-30
- **Feature**: [`remaining-phases-roadmap`](../features/remaining-phases-roadmap/brief.md) · **Supersedes**: none · **Superseded by**: none

## Context
Neither an untrusted 25 Hz VLA model output nor an unauthenticated UDP swarm packet may command velocities outside the quadruped's verified kinematic envelope (`0..MAX_VEL`) or spatial corridor (`0..MAX_CORRIDOR_POS`). On the 500 Hz hot path, capability and authenticity checks must execute in constant time with zero heap allocation (`RT-02`, `RT-08`, `RT-17`).

## Options
| Option | Summary | WCET / Jitter | Memory / Cache Layout | Failure Mode | Reversibility | Verdict |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| A | **Fixed-Layout 64-Byte Spatial Security Token + Constant-Time MAC & Envelope Bounds** | `< 1 µs` fixed-size verification; zero syscalls | `#[repr(C, align(64))]` POD struct in `vrka-abi` | Reject frame immediately; fall back to cached `ctrl_ttl` or expire `peer_lease_ttl` | High | **Selected** |
| B | Dynamic X.509 / JSON Web Token parsing per frame | Unbounded parsing + heap allocation | Variable-length heap strings | Violates Law 2 (`RT-02`) and 500 Hz WCET budget | Low | Rejected: violates `RT-02`, `RT-05` |

## Decision
Define a 64-byte cache-line-aligned `SpatialSecurityToken` in `crates/vrka-abi` (`#[repr(C, align(64))]`, verified via `assert_cache_line_aligned!`) carrying the monotonic threat epoch (`shm_threat_epoch` / peer epoch), kinematic capability bounds (`max_vel`, corridor bounds), expiration tick TTL, and a fixed-width keyed MAC tag. Both `vrka-rt` (for SHM chunks) and `vrka-swarm` (for UDP peer leases) validate token bounds, finite numbers (`.is_finite()`), and monotonic epoch/sequence before updating control or obstacle state.

## Invariants
| Rule | How enforced | Where |
| :-- | :-- | :-- |
| RT-03 | `SpatialSecurityToken` is `#[repr(C, align(64))]` with adjacent `assert_cache_line_aligned!(SpatialSecurityToken, 64)` and explicit zeroed padding | `crates/vrka-abi/src/lib.rs` |
| RT-08 | Reject `NaN`, `Inf`, negative or out-of-range velocities (`v \notin 0..MAX_VEL`), and expired TTLs at ingestion | `crates/vrka-abi`, `crates/vrka-swarm` |
| RT-17 | Deny by default on swarm UDP frames; verify MAC tag, monotonic sequence, `peer_pos \in 0..MAX_CORRIDOR_POS`, and `peer_lease_ttl \in 1..MAX_HORIZON_TTL` | `crates/vrka-swarm/src/lib.rs` |

## Hazard, Timing & Failure Model
| Hazard / Failure Mode | Physical / Timing Impact | Mitigation / Safe-State Transition | Verification (`S-xx` / TLC) |
| :-- | :-- | :-- | :-- |
| Corrupted, spoofed, or out-of-bounds velocity/position frame | Unbounded actuation or false obstacle clearing | Immediate frame rejection; spine uses cached `ctrl_ttl` decay toward `STANCE_LOCK` (`ctrl_vel = 0`) | `SeqlockNoTornRead`, `[S-02]`, `[S-05]` |

## ABI Compatibility & Rollback
- **Layout & Alignment**: 64-byte cache-line-aligned POD struct with explicit reserved padding bytes initialized via `const fn new_zeroed()`.
- **Version / Epoch Gating**: Frames with mismatched protocol version or regressed `shm_threat_epoch` are rejected before entering the CBF filter.
- **Rollback**: Revert token layout changes in `vrka-abi`; compile-time size assertions prevent silent partial rollbacks.

## Consequences
- **+** Enforces capability-bounded kinematic envelopes and authenticated swarm leases in `O(1)` time without heap allocation.
- **−** Adds 64 bytes per signed frame header · **Mitigation**: fits in a single L1 hardware cache line (`CACHE_LINE_BYTES = 64`).

## Contracts
- [`crates/vrka-abi/src/lib.rs`](../../crates/vrka-abi/src/lib.rs) · [`crates/vrka-swarm/src/lib.rs`](../../crates/vrka-swarm/src/lib.rs) · [`specs/horizon_lease/vrka_horizon_lease.tla`](../../specs/horizon_lease/vrka_horizon_lease.tla)
