# System Overview (`vrka-vla`)

- **Specs & Formal Verification (`specs/`, `scripts/verify_specs.sh`)**: PlusCal (`pcal.trans`) and TLC (`tlc2.TLC -workers auto`) verification pipeline invoked via `make tla-check` / `make verify-specs`. `specs/horizon_lease/vrka_horizon_lease.tla` and `.cfg` define the Phase 1 single-agent horizon lease state machine skeleton.
- **Rust Real-Time Workspace (`crates/`)**: `#![no_std]` core crates (`vrka-abi`, `vrka-shm`, `vrka-cbf`) and real-time / simulation / swarm crates (`vrka-rt`, `vrka-swarm`, `vrka-ebpf`, `vrka-sim`).
- **Python Proposer (`proposer/`)**: 20 Hz VLA Flow-Matching trajectory proposer (`vrka_proposer`).
