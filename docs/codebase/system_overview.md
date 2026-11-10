# System Overview (`vrka-vla`)

`vrka-vla` (*The Vedic Wolf Pack*) is a deterministic real-time execution and safety architecture for embodied physical AI. It decouples asynchronous high-dimensional Vision-Language-Action (VLA) trajectory chunk generation (`20–25 Hz`) from a deterministic `500 Hz` (`2,000,000 ns` period, `< 50 µs` jitter) real-time control and safety spine.

## Architectural Layers & Phase Status

| Layer / Subsystem | Crate / Directory | Phase & Status | Core Responsibility |
| :-- | :-- | :-- | :-- |
| **Formal Specifications & TLC Verification** | [`specs/`](../../specs/), [`scripts/verify_specs.sh`](../../scripts/verify_specs.sh) | **Phase 1 — Complete (Validated)** | PlusCal (`pcal.trans`) & headless TLC (`tlc2.TLC -workers auto`) model checking via `make tla-check` / `make verify-specs`. [`vrka_horizon_lease.tla`](../../specs/horizon_lease/vrka_horizon_lease.tla) proves `SafetyNoCollision`, `CBFBarrierInvariant`, and `SeqlockNoTornRead`. |
| **Cache-Line ABI & Wait-Free Seqlock IPC** | [`crates/vrka-abi`](../../crates/vrka-abi), [`crates/vrka-shm`](../../crates/vrka-shm) | **Phase 2 — Complete (Validated)** | `#[repr(C, align(64))]` frame headers, trajectory chunks, spatial security tokens (`assert_cache_line_aligned!`), and single-writer / multi-reader wait-free Seqlock IPC. |
| **CBF-QP Safety Shield & 500 Hz Spine** | [`crates/vrka-cbf`](../../crates/vrka-cbf), [`crates/vrka-rt`](../../crates/vrka-rt), [`crates/vrka-ebpf`](../../crates/vrka-ebpf) | **Phase 3 — Complete (Validated)** | `#![no_std]` Control Barrier Function braking shield, 500 Hz horizon TTL decay state machine (`NOMINAL` → `DECEL_FALLBACK` → `STANCE_LOCK`), `PREEMPT_RT` / `mlockall` memory locking, and `aya-rs` kernel jitter tracepoints. |
| **Multi-Agent Wolf-Pack Swarm Leases** | [`crates/vrka-swarm`](../../crates/vrka-swarm), [`specs/pack_swarm/`](../../specs/pack_swarm/) | **Phase 4 — Complete (Validated)** | Non-blocking UDP peer spatial lease broadcast (`PeerLeaseFrame`), IEEE 1588 PTPv2 drift validation, authenticated spatial tokens, and dynamic obstacle horizon aggregation (`EffectiveObstaclePos`). |
| **25 Hz VLA Proposer & Chaos Simulator** | [`proposer/`](../../proposer/), [`crates/vrka-sim`](../../crates/vrka-sim) | **Phase 5 — Complete (Validated)** | Python 25 Hz Flow-Matching VLA action chunk producer (`vrka_proposer`) and deterministic `libmujoco` physics / fault-injection chaos harness (`500 Hz`). |

## Phase 1 Formal Horizon Lease Architecture (`VrkaHorizonLease`)

Implemented and model-checked in [`specs/horizon_lease/vrka_horizon_lease.tla`](../../specs/horizon_lease/vrka_horizon_lease.tla) (with configuration [`vrka_horizon_lease.cfg`](../../specs/horizon_lease/vrka_horizon_lease.cfg)):

1. **Wait-Free Seqlock Protocol (`VLA_Proposer_20Hz` → `Vrka_RT_Spine_500Hz`)**:
   - The proposer increments `shm_seq` to an **odd** value (`WriteBegin`: `shm_seq := (shm_seq + 1) % 4`) while mutating the shared slot (`shm_cmd_vel := -1` sentinel for in-flight torn state).
   - On `WriteCommit`, the proposer writes a valid velocity `v \in 0..MAX_VEL`, horizon lease `ttl \in 1..MAX_HORIZON_TTL`, updates `shm_threat_epoch := (shm_seq + 1) \div 2`, and increments `shm_seq` to an **even** value.
   - The 500 Hz spine accepts a shared-memory slot only when `shm_seq % 2 = 0 /\ shm_chunk_ttl > 0`; otherwise it discards the torn/in-flight read without spinning and falls back to its local cached `ctrl_ttl`.
2. **Deterministic Horizon TTL Decay Ladder (`NOMINAL` → `DECEL_FALLBACK` → `STANCE_LOCK`)**:
   - **Fresh valid Seqlock read (`shm_seq % 2 = 0 /\ shm_chunk_ttl > 0`)**: reloads `ctrl_ttl := shm_chunk_ttl`. Enters `"NOMINAL"` when `shm_chunk_ttl > 1` (candidate velocity `shm_cmd_vel`) or `"DECEL_FALLBACK"` when `shm_chunk_ttl = 1` (candidate velocity `max(shm_cmd_vel - 1, 0)`).
   - **Torn or stale Seqlock read (`shm_seq % 2 # 0 \/ shm_chunk_ttl = 0`)**:
     - `ctrl_ttl > 2`: decrements `ctrl_ttl := ctrl_ttl - 1`, remains `"NOMINAL"`, and re-filters current `ctrl_vel` against `EffectiveObstaclePos`.
     - `ctrl_ttl = 2`: decrements `ctrl_ttl := 1`, transitions to `"DECEL_FALLBACK"`, and steps down candidate velocity `v_dec = max(ctrl_vel - 1, 0)`.
     - `ctrl_ttl <= 1`: sets `ctrl_ttl := 0`, transitions immediately to `"STANCE_LOCK"`, and clamps `ctrl_vel := 0` (`UNCHANGED robot_pos`).
3. **Discrete CBF Braking-Distance Safety Filter & Peer Lease Aggregation (`Peer_Wolf_UDP`)**:
   - Stopping distance at discrete velocity $v$ under unit deceleration per tick: $\text{BrakingDistance}(v) = \lfloor v(v + 1) / 2 \rfloor$.
   - Effective obstacle boundary combines static and active peer leases: $\text{EffectiveObstaclePos} = \text{peer\_pos}$ if $\text{peer\_lease\_ttl} > 0 \land \text{peer\_pos} < \text{THREAT\_POS}$, else $\text{THREAT\_POS}$.
   - Every 500 Hz actuation step selects the maximal velocity $v_{\text{safe}} \in [0, v_{\text{cand}}]$ satisfying forward invariance:
     $$\text{robot\_pos} + v_{\text{safe}} + \text{BrakingDistance}(v_{\text{safe}}) \le \text{EffectiveObstaclePos}$$
     Since $v = 0$ always satisfies $\text{robot\_pos} + \text{BrakingDistance}(\text{ctrl\_vel}) \le \text{EffectiveObstaclePos}$ by inductive invariant `CBFBarrierInvariant`, `SafeVels` is guaranteed non-empty on every tick.
