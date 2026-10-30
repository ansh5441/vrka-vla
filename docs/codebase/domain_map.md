# Domain Map (`vrka-vla`)

| Entity / State Machine | Owning Module | Notes |
| :-- | :-- | :-- |
| `VrkaHorizonLease` (Seqlock + 500 Hz TTL decay + peer lease) | `specs/horizon_lease/vrka_horizon_lease.tla` | Phase 1 PlusCal/TLA+ formal specification skeleton (Law 1 human-owned transitions/invariants) |
| Cache-line ABI descriptors | `crates/vrka-abi` | `#![no_std]`, 64-byte aligned shared memory descriptors (Law 2 & Law 3) |
| Wait-free Seqlock IPC | `crates/vrka-shm` | `#![no_std]` default features, shared-memory transport |
| Control Barrier Function shield | `crates/vrka-cbf` | `#![no_std]` safety filter (Law 1 human-owned barrier math) |

