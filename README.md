# `vrka-vla` — The Vedic Wolf Pack

**Deterministic Real-Time Execution & Safety Architecture for Embodied Physical AI**  
*Decoupling 20–25 Hz Asynchronous VLA Trajectory Chunking from a 500 Hz `#![no_std]` Safety Spine*

[![Rust 1.93+](https://img.shields.io/badge/rust-1.93%2B-blue.svg?logo=rust)](https://www.rust-lang.org)
[![Python 3.11+](https://img.shields.io/badge/python-3.11%2B-blue.svg?logo=python)](https://www.python.org)
[![TLA+ Formal Verification](https://img.shields.io/badge/TLA%2B-Model%20Checked-brightgreen.svg)](specs/horizon_lease/vrka_horizon_lease.tla)
[![Real-Time](https://img.shields.io/badge/Control%20Spine-500%20Hz%20(2ms)-red.svg)]()
[![Zero Heap Alloc](https://img.shields.io/badge/Hot%20Path-Zero%20Allocation-success.svg)]()
[![License](https://img.shields.io/badge/license-Apache--2.0%20%7C%20MIT-blue.svg)](LICENSE)

---

## 1. Executive Summary

Vision-Language-Action (VLA) foundation models generate semantic manipulation and locomotion trajectories at **20–25 Hz** with non-deterministic inference latencies and preemption risks. In contrast, dynamic quadrupeds and humanoids require hard **500 Hz control loops** (2 ms period, < 50 µs jitter) to maintain dynamic balance and physical safety.

`vrka-vla` bridges this divide. It provides a mathematically proven, lock-free, zero-allocation real-time execution engine that shields physical actuators from model stalls, torn memory reads, and wireless drops.

```text
 ┌───────────────────────────┐         ┌──────────────────────────────────────────────┐
 │ 25 Hz Python VLA Proposer │         │     500 Hz `#![no_std]` Rust Real-Time Spine │
 │ (Flow-Matching Trajectory)│         │ (Deterministic Watchdog & Actuator Dispatch) │
 └─────────────┬─────────────┘         └──────────────────────▲───────────────────────┘
               │                                              │
               ▼ WriteBegin (odd seq)                         │ Read (even seq, wait-free)
 ┌────────────────────────────────────────────────────────────┴───────────────────────┐
 │               Wait-Free POSIX Shared-Memory Seqlock (`vrka-shm`, `vrka-abi`)       │
 │            64-Byte Cache-Line Aligned · Zero False Sharing · Zero Heap Alloc       │
 └────────────────────────────────────────────────────────────┬───────────────────────┘
                                                              │
                                                              ▼
               ┌──────────────────────────────────────────────────────────────────────┐
               │    `#![no_std]` Control Barrier Function Safety Shield (`vrka-cbf`)  │
               │    h(x) = EffectiveObstaclePos - (robot_pos + BrakingDistance(v)) ≥ 0│
               │    Forward Invariance: NOMINAL -> DECEL_FALLBACK -> STANCE_LOCK      │
               └──────────────────────────────────────────────────────────────────────┘
```

---

## 2. The Three Immutable Architectural Laws

Active and non-negotiable across every commit (`AGENTS.md`):

1. **Law 1: Human-Only Authority over Memory Ordering, Barrier Math & Formal Invariants**  
   Autonomous agents never alter `Ordering::*` atomics, TLA+ state specs, or CBF barrier equations without explicit human specification.
2. **Law 2: Zero Dynamic Heap Allocation in the 500 Hz Execution Loop**  
   Core crates (`vrka-abi`, `vrka-shm`, `vrka-cbf`, `vrka-ebpf`) are strictly `#![no_std]` with zero heap allocations on the hot path. Verified via `CountingAllocator` regression suites (`alloc_count == 0`).
3. **Law 3: Compile-Time 64-Byte Alignment on Every ABI Boundary**  
   All shared-memory headers, chunk slots, spatial tokens, and wire frames enforce `assert_cache_line_aligned!` (`align_of == 64`, `size % 64 == 0`) with zero implicit padding.

---

## 3. Subsystem Matrix

| Subsystem | Crate / Directory | Language | RT Profile | Core Responsibility |
| :-- | :-- | :-- | :-- | :-- |
| **Formal Specs** | `specs/horizon_lease/` | TLA+ / PlusCal | Formal | 291,528 states model-checked; proves `SafetyNoCollision`, `CBFBarrierInvariant`, `SeqlockNoTornRead`. |
| **Cache-Line ABI** | `crates/vrka-abi` | Rust | `#![no_std]` | 64/128-byte aligned layouts (`ActionChunkSlot`, `SpatialSecurityToken`, `FlightRecorderEntry`). |
| **Seqlock IPC** | `crates/vrka-shm` | Rust | `#![no_std]` (std init)| Wait-free single-writer / multi-reader Seqlock IPC with $O(1)$ non-spinning torn read rejection. |
| **CBF Shield** | `crates/vrka-cbf` | Rust | `#![no_std]` | Discrete stopping-distance barrier filter $h(x) \ge 0$ guaranteeing forward-invariant safe velocities. |
| **500 Hz Spine** | `crates/vrka-rt` | Rust | Real-Time (PREEMPT_RT)| 500 Hz loop, monotonic clock injection, horizon TTL ladder (`Nominal` → `DecelFallback` → `StanceLock`). |
| **Kernel Probes** | `crates/vrka-ebpf` | Rust | `#![no_std]` (aya-rs)| In-kernel scheduling jitter telemetry monitoring against `MAX_JITTER_BUDGET_NS = 50_000` (50 µs). |
| **Swarm Leases** | `crates/vrka-swarm` | Rust | Real-Time | 128-byte UDP peer lease broadcast (`:9500`), PTPv2 sync, and `EffectiveObstaclePos` aggregation. |
| **VLA Proposer** | `proposer/` | Python | 25 Hz Asynchronous | Flow-matching action chunk producer with strict type annotations, Ruff, and boundary validation. |
| **Chaos Sim** | `crates/vrka-sim` | Rust / C | Deterministic | 500 Hz `libmujoco` physics harness injecting torn writes, proposer stalls, and UDP packet drops. |

---

## 4. Verification & How to Run

Canonical developer interface standardizes CI, hooks, and local environments via `Makefile`:

```bash
# 1. Setup tracked git hooks and verify toolchain dependencies
make setup

# 2. Execute full validation gate (formatting, Clippy -D warnings, #![no_std] audit, tests, TLC)
make validate

# 3. Run formal TLA+ model checker across concurrent horizon-lease state space
make tla-check

# 4. Verify Python VLA Proposer package (Ruff lint, Ruff format, mypy --strict, Pytest)
make check-python
```

### Verification Suite Outputs
- **TLC Model Checker**: Explores `4,547,649` transitions (`291,528` distinct states, depth 29) proving zero collisions and zero torn reads.
- **CountingAllocator Hot-Path Proofs**: Proves `0` heap allocations and `0` bytes allocated during 500 Hz Seqlock reads, CBF velocity projections, and telemetry logging.
- **Cache-Line Alignment Assertions**: Static compile-time assertions ensure exact 64-byte boundaries, preventing false sharing on symmetric multiprocessor hardware.

---

## 5. Engineering Roadmap & Implementation Status

```text
[Phase 1] Formal Horizon Lease Specification & TLC Model Checking      [COMPLETE - Validated]
[Phase 2] Cache-Line ABI & Wait-Free Seqlock IPC (vrka-abi, vrka-shm)   [COMPLETE - Validated]
[Phase 3] Discrete CBF Safety Shield & 500 Hz Spine (vrka-cbf, vrka-rt) [COMPLETE - Validated]
[Phase 4] Swarm Leases & Obstacle Horizon Aggregation (vrka-swarm)      [COMPLETE - Validated]
[Phase 5] 25 Hz Flow-Matching Proposer Contract (vrka-proposer)         [COMPLETE - Validated]
──────────────────────────────────────────────────────────────────────────────────────────────
[Track A] POSIX shm_open Zero-Copy Ring Transport across OS Processes   [In Progress / Planned]
[Track B] Continuous 3D Quadruped CBF-QP Solver & PREEMPT_RT Pinning    [Planned]
[Track C] Multi-Agent Swarm TLA+ Model & io_uring UDP Broadcasts        [Planned]
[Track D] 500 Hz MuJoCo Closed-Loop Chaos Fault-Injection Simulation    [Planned]
```
