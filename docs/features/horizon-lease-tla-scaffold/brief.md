# Brief: Phase 1 TLA+ / PlusCal Horizon Lease Scaffold & TLC Runner

- **Slug**: `horizon-lease-tla-scaffold` · **Tier**: S · **Money**: false · **PII**: false · **Type**: feature
- **Status**: Approved · **Created**: 2026-10-30
- **ADRs**: [003-wait-free-seqlock-ipc](../../adr/003-wait-free-seqlock-ipc.md), [004-cbf-qp-safety-shield](../../adr/004-cbf-qp-safety-shield.md), [005-multi-agent-pack-leases](../../adr/005-multi-agent-pack-leases.md)
- **Tier evidence**: ≤3 reversible tasks (~220 lines) for local TLA+/PlusCal tooling, empty specification skeleton, and cheat sheet; no money, PII, schema, auth, or external service boundary.

## Problem
[scripts/verify_specs.sh](../../../scripts/verify_specs.sh) currently relies on `command -v java` (which resolves to the unconfigured `/usr/bin/java` macOS stub instead of Homebrew OpenJDK at `/opt/homebrew/opt/openjdk/bin/java`), lacks `<spec_name>` filtering and explicit TLC output parsing for invariant/deadlock/parse failures, and `specs/tools/tla2tools.jar` is not yet downloaded. Furthermore, [specs/horizon_lease/](../../../specs/horizon_lease/) has no `.tla`/`.cfg` skeleton and `specs/README.md` does not exist.

## Scope
- **In**:
  1. Download `tla2tools.jar` to `specs/tools/tla2tools.jar`, update [.gitignore](../../../.gitignore) to ignore `specs/tools/*.jar`, enhance [scripts/verify_specs.sh](../../../scripts/verify_specs.sh) to accept an optional `<spec_name>`, resolve functional macOS Java (`JAVA_HOME` / Homebrew OpenJDK), run `pcal.trans` and `tlc2.TLC -workers auto`, and parse TLC output to fail closed on any invariant violation, deadlock, or parse error; add `make tla-check` to [Makefile](../../../Makefile).
  2. Scaffold [specs/horizon_lease/vrka_horizon_lease.tla](../../../specs/horizon_lease/vrka_horizon_lease.tla) and [specs/horizon_lease/vrka_horizon_lease.cfg](../../../specs/horizon_lease/vrka_horizon_lease.cfg) with constants, state variables, placeholder `define ... end define;` markers (`BrakingDistance(v)`, `SafetyNoCollision`, `CBFBarrierInvariant`, `SeqlockNoTornRead`), and empty PlusCal process stubs (`VLA_Proposer_20Hz`, `Vrka_RT_Spine_500Hz`, `Peer_Wolf_UDP`) with `TODO` comments.
  3. Create [specs/README.md](../../../specs/README.md) with a concise 1-page PlusCal syntax cheat sheet for Go/Rust systems engineers and exact terminal commands.
- **Out**: Implementing state transition logic, Seqlock transitions, horizon TTL decay ladder, or CBF barrier math/clamps (strictly reserved for the human architect under Architectural Law 1).

## Decisions
| ID | Dilemma | Chosen | Why / trade-off accepted |
| :-- | :--- | :--- | :--- |
| D-01 | macOS Java resolution when `/usr/bin/java` stub fails | Probe `JAVA_HOME/bin/java`, PATH `java -version`, then `/opt/homebrew/opt/openjdk/bin/java` | Works out-of-the-box with Homebrew OpenJDK 25 without requiring system-wide root symlinks |
| D-02 | Skeleton runnable out-of-the-box with `pcal.trans` and `tlc2.TLC` without violating Law 1 | Use `TRUE` placeholder definitions for the 3 invariants and no-op `skip;` labels with `TODO` comments in each process stub | Allows `make tla-check` to translate PlusCal and pass TLC immediately while leaving all transition logic and safety math to the human |

## Scenarios
```gherkin
@S-01
Scenario: PlusCal translation and headless TLC verification succeed on the horizon lease skeleton
  Given specs/tools/tla2tools.jar is present and vrka_horizon_lease.tla/.cfg are scaffolded
  When `./scripts/verify_specs.sh vrka_horizon_lease` or `make tla-check` is executed
  Then `pcal.trans` translates the PlusCal block and `tlc2.TLC -workers auto` completes with zero errors and exit code 0

@S-02
Scenario: CLI runner fails closed on invariant violation, deadlock, parse error, or unknown spec
  Given a spec run whose TLC output contains an invariant violation, deadlock, or parse error, or a non-existent `<spec_name>`
  When `./scripts/verify_specs.sh <spec_name>` is executed
  Then the script exits with a non-zero status code and reports the failure

@S-03
Scenario: PlusCal quick-reference cheat sheet and gitignore hygiene are in place
  Given `specs/README.md` and `.gitignore`
  When inspected by the engineer and git status
  Then `specs/README.md` documents `:=`, `with x \in S do`, atomic labels, `await`, `=>`, and TLC CLI commands, and `specs/tools/*.jar` is ignored by git
```

## Blast Radius
| Kind | Items |
| :-- | :-- |
| Modules | [scripts/verify_specs.sh](../../../scripts/verify_specs.sh), [Makefile](../../../Makefile), [.gitignore](../../../.gitignore), [specs/horizon_lease/vrka_horizon_lease.tla](../../../specs/horizon_lease/vrka_horizon_lease.tla), [specs/horizon_lease/vrka_horizon_lease.cfg](../../../specs/horizon_lease/vrka_horizon_lease.cfg), [specs/README.md](../../../specs/README.md) |
| Tables | none |
| External | GitHub Releases (`tlaplus/tlaplus` latest `tla2tools.jar` download into untracked `specs/tools/tla2tools.jar`) |
| Flag | none |
