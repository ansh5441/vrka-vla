# Horizon Lease TLA+ Specifications (`specs/horizon_lease/`)

Contains the Phase 1 PlusCal/TLA+ formal specification and model configuration for the single-agent + peer horizon lease state machine (`VrkaHorizonLease`), authored and verified under Architectural Law 1 (`RT-01`):

- [`vrka_horizon_lease.tla`](./vrka_horizon_lease.tla): PlusCal algorithm (`VLA_Proposer_20Hz`, `Vrka_RT_Spine_500Hz`, `Peer_Wolf_UDP`) and translated TLA+ specification proving:
  - `SafetyNoCollision == robot_pos <= EffectiveObstaclePos`
  - `CBFBarrierInvariant == (robot_pos + BrakingDistance(ctrl_vel)) <= EffectiveObstaclePos`
  - `SeqlockNoTornRead == ctrl_vel \in 0..MAX_VEL /\ ctrl_ttl \in 0..MAX_HORIZON_TTL /\ ((shm_seq % 2 = 0) => (shm_cmd_vel \in 0..MAX_VEL))`
- [`vrka_horizon_lease.cfg`](./vrka_horizon_lease.cfg): Bounded TLC model configuration (`MAX_CORRIDOR_POS = 10`, `THREAT_POS = 7`, `MAX_HORIZON_TTL = 3`, `MAX_VEL = 2`), verified via `make tla-check` / `./scripts/verify_specs.sh vrka_horizon_lease`.
- Architectural decisions and hazard models: [ADR 003](../../docs/adr/003-wait-free-seqlock-ipc.md), [ADR 004](../../docs/adr/004-cbf-qp-safety-shield.md), and [ADR 005](../../docs/adr/005-multi-agent-pack-leases.md).
