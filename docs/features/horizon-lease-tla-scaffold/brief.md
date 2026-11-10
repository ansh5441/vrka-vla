# Brief: Phase 1 TLA+ / PlusCal Horizon Lease Specification & TLC Runner

- **Slug**: `horizon-lease-tla-scaffold` · **Tier**: L · **Law1**: true · **HotPath**: false · **ABI**: false · **Type**: feature
- **Status**: Validated · **Created**: 2026-10-30
- **ADRs**: [001-flow-matching-chunking](../../adr/001-flow-matching-chunking.md), [003-wait-free-seqlock-ipc](../../adr/003-wait-free-seqlock-ipc.md), [004-cbf-qp-safety-shield](../../adr/004-cbf-qp-safety-shield.md), [005-multi-agent-pack-leases](../../adr/005-multi-agent-pack-leases.md)
- **Tier evidence**: Law 1 (`law1: true`) formal PlusCal/TLA+ specification in [`specs/horizon_lease/vrka_horizon_lease.tla`](../../../specs/horizon_lease/vrka_horizon_lease.tla) defining Seqlock transitions, 500 Hz TTL decay ladder, peer lease obstacle aggregation, and discrete CBF braking-distance invariants.

## Problem
[`scripts/verify_specs.sh`](../../../scripts/verify_specs.sh) needed macOS OpenJDK resolution, `<spec_name>` filtering, and fail-closed TLC output verification, while [`specs/horizon_lease/vrka_horizon_lease.tla`](../../../specs/horizon_lease/vrka_horizon_lease.tla) and [`.cfg`](../../../specs/horizon_lease/vrka_horizon_lease.cfg) needed the complete Phase 1 formal specification of the wait-free Seqlock IPC, 500 Hz horizon TTL decay state machine (`NOMINAL` → `DECEL_FALLBACK` → `STANCE_LOCK`), peer UDP lease tightening, and discrete CBF safety invariants (`SafetyNoCollision`, `CBFBarrierInvariant`, `SeqlockNoTornRead`).

## Scope
- **In**:
  1. Configure `specs/tools/tla2tools.jar` (git-ignored), enhance [`scripts/verify_specs.sh`](../../../scripts/verify_specs.sh) and [`scripts/test_verify_specs.sh`](../../../scripts/test_verify_specs.sh) to translate PlusCal (`pcal.trans`), run headless TLC (`tlc2.TLC -workers auto`), verify a non-trivial state graph (`> 1` distinct states) with zero invariant/deadlock errors, and add `make tla-check` to [`Makefile`](../../../Makefile).
  2. Author and model-check [`specs/horizon_lease/vrka_horizon_lease.tla`](../../../specs/horizon_lease/vrka_horizon_lease.tla) and [`vrka_horizon_lease.cfg`](../../../specs/horizon_lease/vrka_horizon_lease.cfg) with the human-specified Law 1 operators and process transitions (`VLA_Proposer_20Hz`, `Vrka_RT_Spine_500Hz`, `Peer_Wolf_UDP`).
  3. Document the PlusCal quick-reference cheat sheet in [`specs/README.md`](../../../specs/README.md) and record the validated Phase 1 architecture in [`docs/adr/`](../../adr/INDEX.md) and [`docs/codebase/`](../../codebase/system_overview.md).
- **Out**: Rust `#![no_std]` Seqlock/CBF implementation in `crates/` and Python proposer implementation (scoped in [`docs/features/remaining-phases-roadmap/brief.md`](../remaining-phases-roadmap/brief.md)).

## Law 1 Human Specification
- **Approved by**: Human Architect (authored directly in [`specs/horizon_lease/vrka_horizon_lease.tla`](../../../specs/horizon_lease/vrka_horizon_lease.tla))
- **Memory Ordering (`Ordering::*`)**: N/A in Phase 1 TLA+ model (modeled via atomic labels `WriteBegin` odd `shm_seq := (shm_seq + 1) % 4` with sentinel `shm_cmd_vel := -1` and `WriteCommit` even `shm_seq := (shm_seq + 1) % 4`).
- **Formal TLA+ / PlusCal (`specs/`)**:
  - `BrakingDistance(v) == (v * (v + 1)) \div 2`
  - `EffectiveObstaclePos == IF peer_lease_ttl > 0 /\ peer_pos < THREAT_POS THEN peer_pos ELSE THREAT_POS`
  - `SafetyNoCollision == robot_pos <= EffectiveObstaclePos`
  - `CBFBarrierInvariant == (robot_pos + BrakingDistance(ctrl_vel)) <= EffectiveObstaclePos`
  - `SeqlockNoTornRead == ctrl_vel \in 0..MAX_VEL /\ ctrl_ttl \in 0..MAX_HORIZON_TTL /\ ((shm_seq % 2 = 0) => (shm_cmd_vel \in 0..MAX_VEL))`
  - Processes: `VLA_Proposer_20Hz` (`WriteBegin` → `WriteCommit`), `Vrka_RT_Spine_500Hz` (`SpineTick` with fresh-read vs. cached-TTL decay `ctrl_ttl > 2` `NOMINAL`, `ctrl_ttl = 2` `DECEL_FALLBACK`, `ctrl_ttl <= 1` `STANCE_LOCK`), and `Peer_Wolf_UDP` (`PeerStep` with `p \in (robot_pos + BrakingDistance(ctrl_vel))..MAX_CORRIDOR_POS`).
- **CBF-QP Barrier Math (`vrka-cbf`)**: Discrete forward-invariant velocity filter `SafeVels = {v \in 0..v_cand : robot_pos + v + BrakingDistance(v) <= EffectiveObstaclePos}`, selecting maximal `v_safe \in SafeVels`.

## Decisions
| ID | Dilemma | Chosen | Why / trade-off accepted |
| :-- | :--- | :--- | :--- |
| D-01 | macOS Java resolution when `/usr/bin/java` stub fails | Probe `JAVA_HOME/bin/java`, PATH `java -version`, then `/opt/homebrew/opt/openjdk/bin/java` | Works out-of-the-box with Homebrew OpenJDK without requiring root symlinks |
| D-02 | Bounding `shm_seq` in finite-state TLC model checking | Wrap `shm_seq := (shm_seq + 1) % 4` (`0,1,2,3`) and derive `shm_threat_epoch := (shm_seq + 1) \div 2` | Keeps TLC state space finite while preserving exact odd/even Seqlock parity invariants |
| D-03 | Peer obstacle reservation admission bound | Constrain new peer leases to `p \in (robot_pos + BrakingDistance(ctrl_vel))..MAX_CORRIDOR_POS` | Prevents unshieldable instantaneous teleports inside the ego robot's committed braking distance (`ADR 005`) |

## Scenarios
```gherkin
@S-01
Scenario: PlusCal translation and headless TLC verification prove all 3 invariants over the full state graph
  Given specs/tools/tla2tools.jar and the complete VrkaHorizonLease specification in vrka_horizon_lease.tla/.cfg
  When `./scripts/verify_specs.sh vrka_horizon_lease` or `make tla-check` is executed
  Then `pcal.trans` translates the PlusCal block and `tlc2.TLC -workers auto` explores > 1 distinct states with 0 invariant violations and exit code 0

@S-02
Scenario: CLI runner fails closed on invariant violation, deadlock, parse error, or unknown spec
  Given a spec run whose TLC output contains an invariant violation, deadlock, or parse error, or a non-existent `<spec_name>`
  When `./scripts/verify_specs.sh <spec_name>` is executed
  Then the script exits with a non-zero status code and reports the failure

@S-03
Scenario: PlusCal quick-reference cheat sheet and gitignore hygiene are in place
  Given `specs/README.md` and `.gitignore`
  When inspected by `./scripts/test_verify_specs.sh`
  Then `specs/README.md` documents `:=`, `with x \in S do`, atomic labels, `await`, `=>`, and TLC CLI commands, and `specs/tools/*.jar` is ignored by git
```

## Blast Radius
| Kind | Items |
| :-- | :-- |
| Crates / Packages | [`scripts/verify_specs.sh`](../../../scripts/verify_specs.sh), [`scripts/test_verify_specs.sh`](../../../scripts/test_verify_specs.sh), [`Makefile`](../../../Makefile), [`.gitignore`](../../../.gitignore) |
| ABI / Wire Structs | none (Phase 1 formal specification) |
| Formal Specs | [`specs/horizon_lease/vrka_horizon_lease.tla`](../../../specs/horizon_lease/vrka_horizon_lease.tla), [`specs/horizon_lease/vrka_horizon_lease.cfg`](../../../specs/horizon_lease/vrka_horizon_lease.cfg), [`specs/README.md`](../../../specs/README.md) |
| Feature Flag | none |
