---
description: Always-on Embodied Robotics & Deterministic Real-Time Systems Developer Guide — rules RT-01..RT-21 for Law 1/2/3 invariants, 500 Hz spine, Seqlock IPC, CBF-QP safety, C-FFI, PTP time, verification, and Rust/TLA+/Python/C
trigger: always_on
---

# Embodied Robotics & Deterministic Real-Time Systems Developer Guide

**Applies to:** every change in every robotics and real-time systems repository, by every engineer and agent — `#![no_std]` core crates (`vrka-abi`, `vrka-shm`, `vrka-cbf`), 500 Hz real-time execution daemons (`vrka-rt`, `vrka-swarm`), kernel eBPF telemetry (`vrka-ebpf`), deterministic physics simulation (`vrka-sim`), formal TLA+/PlusCal specifications (`specs/`), and asynchronous VLA trajectory proposers (`proposer/`).
**Standards:** ISO 13482 / IEC 61508 (SIL-3 Physical Safety), ISO 10218, MISRA C / High-Assurance Rust, IEEE 1588 PTPv2, Linux `PREEMPT_RT` / `SCHED_DEADLINE`, TLA+ Formal Verification.

## 0. How This Guide Works

- **Always on.** This guide applies to every change, however small. Rules carry stable IDs (`RT-xx`); cite them in reviews, commits, ADRs, `// SAFETY:` comments, and `TODO(debt)` notes. IDs are never renumbered or reused.
- **Guide vs. Vrka 40-series skills.** This guide defines *what must be true* of code. The Vrka skills (`/vrka-41-discover` → `45`) are the *process* for changes large or risky enough to need formal planning and locked contracts. Vrka cites these IDs and never restates or relaxes them; if a skill and this guide disagree, this guide and [`AGENTS.md`](../../AGENTS.md) win.
- **When to use Vrka.** Start with `/vrka-41-discover` when a change touches **Law 1 (`law1`)** (atomic `Ordering::*`, `specs/*.tla`, or `vrka-cbf` barrier math — at any size), the **500 Hz hot path (`hotpath`)** (`vrka-abi`, `vrka-shm`, `vrka-cbf`, `vrka-rt`, `vrka-swarm`, `vrka-ebpf`), an **ABI / FFI boundary (`abi`)** (`#[repr(C)]`, shared memory, UDP wire packets, `libmujoco`, `osqp`, `io_uring`, `libc`), a safety state machine, or is expected to exceed ~200 changed lines. Anything smaller on the cold path (docs, build scripts, contained non-RT bug fix with its regression test) follows this guide directly, with no Vrka artifacts.
- **Precedence.** [`AGENTS.md`](../../AGENTS.md) Three Immutable Laws > Physical Safety & ISO/IEC Standards > this guide > repo-local conventions. Repo-local rules may be stricter, never weaker.
- **Existing violations.** Fix violations in code you are already changing. If a full fix exceeds the task, add `TODO(debt): RT-xx <reason>` at the site and record it: in Vrka, as a `followups` entry in `tasks.yaml`; otherwise, under a **Debt** heading in the PR description. Never refactor untouched code to satisfy this guide (`RT-14`).

## Rule Index

Vrka packets copy the one-line text below verbatim. `law1` = atomic ordering, TLA+/PlusCal specs, or CBF-QP barrier math (§1). `hotpath` = 500 Hz control spine & `#![no_std]` core crates (§3). `abi` = shared-memory layouts, wire frames, and C-FFI boundaries (§4).

| ID | Rule | Scope |
| :-- | :--- | :-- |
| RT-01 | Law 1 Human-Only Authority: never author or modify atomic `Ordering::*`, TLA+/PlusCal specs (`specs/`), or CBF-QP barrier equations (`vrka-cbf`) without explicit human specification; stop and escalate immediately | law1 |
| RT-02 | Law 2 Zero Hot-Path Heap Allocation: `#![no_std]` without `alloc`/`std` in `vrka-abi`, `vrka-shm` (default), `vrka-cbf`, and `vrka-ebpf`; pre-allocate and `mlockall` arenas in `vrka-rt`/`vrka-swarm`; prove `alloc_count == 0` with `CountingAllocator` | hotpath |
| RT-03 | Law 3 Compile-Time ABI & Alignment Assertions: every `#[repr(C, align(64))]` or FFI struct must have an adjacent `assert_cache_line_aligned!` or `const _: () = assert!(...)` size/alignment check and zero implicit padding | abi |
| RT-04 | Fail-Safe Deterministic Degradation: never silently fallback, default a trajectory, or ignore an error; transition deterministically `NOMINAL` → `DECEL_FALLBACK` → `STANCE_LOCK` (`ctrl_vel = 0`) when horizon TTL or safety invariants fail | all |
| RT-05 | Panic-Free & Syscall-Free 500 Hz Spine: deny `unwrap`, `expect`, `panic!`, `todo!`, `unimplemented!`, dynamic dispatch (`dyn`), locking mutexes, or blocking OS syscalls on the 500 Hz loop; bound WCET < 2 ms (jitter < 50 µs) | hotpath |
| RT-06 | Wait-Free Seqlock & Epoch Integrity: single-writer / multi-reader cache-line-isolated Seqlock IPC; odd sequence = write in progress; readers verify even sequence + matching epoch + CRC/bounds before accepting a frame | hotpath, abi |
| RT-07 | Bounded Horizon Lease & Dead-Man Watchdog: every VLA chunk and peer UDP lease carries a monotonic tick TTL (`shm_chunk_ttl`, `peer_lease_ttl`) decremented every 500 Hz tick; stale or expired leases never actuate motion | all |
| RT-08 | Numerical Determinism & NaN/Inf Rejection: reject `NaN`, `Inf`, and denormals at every sensor, proposer, and QP boundary; use fixed-point/integer ticks for sequences and leases; enforce bounded-iteration QP solvers with safe fallback | all |
| RT-09 | Zero Undocumented `unsafe` & Zero Lint Suppression: every `unsafe` block/fn requires a `// SAFETY:` proof of pointer validity, alignment, aliasing, and lifetime; forbid `#[allow(...)]`, `# type: ignore`, `# noqa`, and `as Any` | all |
| RT-10 | Pure Deterministic Control Core & Injected Monotonic Clock: keep kinematics, TTL decay, and barrier evaluation pure functions over immutable value types; inject monotonic tick/nanosecond clocks; never read ambient wall-clock time on the hot path | all |
| RT-11 | Bounded Complexity & Stack Hygiene: functions < 30 lines; never push a production file past 200 lines or add responsibilities to one already past it; bound stack frames (`clippy::large_stack_arrays = "warn"`) and forbid recursion | all |
| RT-12 | Zero-Allocation Telemetry & Lock-Free Black-Box Flight Recorder: never format strings or perform file/stdout I/O on the 500 Hz loop; emit fixed-size binary frames to a lock-free ring buffer or eBPF tracepoint (`vrka-ebpf`) | hotpath |
| RT-13 | Verification Pyramid: regression test first for bugs; `CountingAllocator` zero-alloc test for hot-path functions; property-based/Kani/Miri checks for ABI & math; headless TLC (`make verify-specs`) for concurrency/lease state machines | all |
| RT-14 | Surgical Diffs & Documentation Integrity: no unrelated edits; preserve all existing `///` docstrings, `// SAFETY:` comments, and architectural headers | all |
| RT-15 | Hardware & C-FFI Isolation (`libmujoco`, `osqp`, `io_uring`, `libc`): encapsulate raw pointers in safe Rust RAII/arena wrappers at adapter edges; enforce single crate versions via `cargo deny check` (`multiple-versions = "deny"`) | abi |
| RT-16 | Monotonic Time & IEEE 1588 PTP Synchronization: represent real-time deadlines and trace timestamps as `u64` nanoseconds from `CLOCK_MONOTONIC_RAW` / PTP hardware clock; forbid `SystemTime` or naive `datetime` in control/telemetry | all |
| RT-17 | Spatial Security & Authenticated Peer Leases: validate cryptographic MAC / spatial security token, bounds, and monotonic sequence number on every `vrka-swarm` peer frame before updating obstacle horizons | all |
| RT-18 | Non-Blocking `io_uring` & Bounded Retry Discipline: all swarm and IPC I/O uses pre-registered buffers and non-blocking submission/completion rings; never retry a timed-out actuator or network frame inside a 500 Hz tick | hotpath |
| RT-19 | Deterministic Replay & Black-Box Audit Trail: every safety shield intervention, mode transition (`NOMINAL` → `DECEL_FALLBACK` → `STANCE_LOCK`), and lease expiry must record a deterministic, replayable black-box telemetry event with seed and tick | all |
| RT-20 | Linux Real-Time Isolation (`PREEMPT_RT`): pin 500 Hz threads to isolated cores (`isolcpus`, `SCHED_FIFO`/`SCHED_DEADLINE`), lock physical pages (`mlockall(MCL_CURRENT \| MCL_FUTURE)`), and pre-fault stacks before entering the spine loop | hotpath |
| RT-21 | Canonical Toolchain & Supply-Chain Hygiene: `Makefile` targets (`make validate`, `make lint`, `make test`, `make verify-specs`, `make check-no-std`, `make deny`) are the sole operational interface; `Cargo.lock` and `uv.lock` committed and frozen | all |

---

## 1. Core Invariants & The Three Immutable Laws (RT-01..RT-04, RT-21)

- **Law 1 — Human-Only Authority over Memory Ordering, Formal Specs, and Barrier Math (RT-01).** Autonomous and pair-programming agents must **never** author or modify:
  1. Atomic memory ordering (`Ordering::Acquire`, `Ordering::Release`, `Ordering::AcqRel`, `Ordering::SeqCst`, `Ordering::Relaxed`) or fences (`atomic::fence`, `compiler_fence`) on synchronization primitives in production crates (`vrka-abi`, `vrka-shm`, `vrka-rt`, `vrka-swarm`).
  2. Formal TLA+ / PlusCal specifications or model configurations under `specs/` (`*.tla`, `*.cfg`).
  3. Control Barrier Function (CBF-QP) barrier equations ($h(x)$), Lie derivatives ($L_f h$, $L_g h$), class-$\mathcal{K}$ functions ($\alpha(h)$), or QP safety constraints in `crates/vrka-cbf`.
  If a task requires introducing or modifying any of these constructs and the human has not provided the exact specification, **stop immediately and request the specification from the human architect**.
- **Law 2 — Zero Dynamic Heap Allocation in the 500 Hz Execution Loop (RT-02).** `crates/vrka-abi`, `crates/vrka-cbf`, and `crates/vrka-ebpf` are unconditionally `#![no_std]` and never link `std` or `alloc`. `crates/vrka-shm` is `#![no_std]` under default features (`#![cfg_attr(not(feature = "std"), no_std)]`). Every hot-path routine must be covered by a `CountingAllocator` integration test proving `alloc_count == 0` and `alloc_bytes == 0`.
- **Law 3 — Compile-Time Size & Alignment Assertions on Every ABI / FFI Boundary (RT-03).** Every `#[repr(C, align(64))]` struct must invoke `vrka_abi::assert_cache_line_aligned!(StructName, EXPECTED_BYTE_SIZE)` immediately adjacent to the type definition. Non-64-byte C-FFI descriptors must have an adjacent `const _: () = assert!(core::mem::size_of::<T>() == N && core::mem::align_of::<T>() == A);`.
- **Fail-safe deterministic degradation (RT-04).** In embodied physical AI, "fail closed" means **fail into a physically safe state**. When an invariant, horizon TTL, Seqlock check, or sensor frame fails, never extrapolate an unverified trajectory, hold an unshielded velocity, or panic. Transition deterministically through the formal state machine (`NOMINAL` → `DECEL_FALLBACK` → `STANCE_LOCK` where `ctrl_vel = 0`), emit a binary black-box event (`RT-12`), and return an explicit typed error/status.
- **Single source of truth.** Each physical and logical state machine has exactly one owning crate:
  - `vrka-abi`: cache-line ABI descriptors, frame headers, spatial token layouts, alignment macros.
  - `vrka-shm`: wait-free Seqlock shared-memory transport between the 20–25 Hz proposer and 500 Hz spine.
  - `vrka-cbf`: `#![no_std]` Control Barrier Function safety filter and QP shield.
  - `vrka-rt`: 500 Hz real-time control loop, horizon lease decay, mode state machine, actuator dispatch.
  - `vrka-swarm`: `io_uring` UDP peer lease broadcast and obstacle horizon aggregation.
  - `vrka-ebpf`: kernel tracepoints and scheduling jitter probes (`MAX_JITTER_BUDGET_NS = 50_000`).
  - `vrka-sim`: deterministic `libmujoco` physics and chaos fault-injection harness.
  - `proposer/`: asynchronous 20–25 Hz Python VLA trajectory chunk generator (`vrka_proposer`).
- **Toolchain (RT-21).** `make setup | fmt | lint | typecheck | test | verify-specs | check-no-std | check-python | deny | validate` behave identically locally, in git hooks (`.githooks/`), in CI, and for agents. Justify every new dependency against `deny.toml` (`cargo deny check`). Lockfiles (`Cargo.lock`, `uv.lock`) are committed and frozen.

## 2. Architecture & Code Shape (RT-10, RT-11)

- **Pure control core.** Kinematics, horizon TTL decay, braking distance calculations, and CBF barrier evaluations are pure deterministic functions over immutable value types (`Copy` structs), completely detached from OS syscalls, `mmap`, `io_uring`, sockets, or hardware drivers. Side effects (shared memory mapping, network rings, hardware clocks, actuator buses) sit behind explicit adapter boundaries in `vrka-rt` and `vrka-swarm`.
- **No dynamic dispatch or recursion on the hot path.** Use static dispatch (generics / monomorphization or exhaustive `match` over closed `enum`s) so the compiler can inline and bound instruction-cache footprint. Recursion is prohibited across the workspace (`RT-11`).
- **Stack hygiene.** Respect `clippy::large_stack_arrays = "warn"`. Pass large pre-allocated workspaces by `&mut` reference from locked static arenas rather than allocating multi-kilobyte arrays on the call stack.
- **Oversized files (RT-11).** Keep functions `< 30` lines and production files `≤ 200` lines. A file already past 200 lines may receive surgical fixes (`≲ 20` lines), not new responsibilities: put new structs or functions in a focused submodule and mark the old file `TODO(debt): RT-11`. Tests, TLA+ translations (`specs/*.tla`), and generated bindings are exempt.

## 3. Real-Time Execution, Control Math & IPC (RT-05..RT-08, RT-19)

### 500 Hz Spine & Timing Budget (RT-05)
- **Period & WCET:** The `vrka-rt` control loop executes at **500 Hz** (`2,000,000 ns` period). Total Worst-Case Execution Time (WCET) per tick must remain strictly bounded below the period, with scheduling jitter under `MAX_JITTER_BUDGET_NS` (`50,000 ns` / `50 µs`).
- **Forbidden constructs on the hot path:**
  - Panicking paths: `.unwrap()`, `.expect()`, `panic!()`, `todo!()`, `unimplemented!()`, `unreachable!()`, and unchecked slice indexing `slice[i]` (use `.get(i)` or compile-time fixed-length array references `&[T; N]`).
  - Heap allocation: `Vec`, `Box`, `String`, `Arc`, `Rc`, `BTreeMap`, `HashMap`, `format!()`.
  - Blocking synchronization or OS syscalls: `std::sync::Mutex`, `RwLock`, `Condvar`, `thread::sleep`, file I/O, socket syscalls, or dynamic memory allocation (`brk`/`mmap`).

### Wait-Free Seqlock & Horizon Lease Protocol (RT-06, RT-07)
- **Seqlock invariants (`SeqlockNoTornRead`):**
  - The 20–25 Hz VLA proposer writes action chunks into a `#[repr(C, align(64))]` shared-memory slot (`vrka-shm`).
  - Writing increments `shm_seq` to an **odd** value before modifying payload fields and increments `shm_seq` to an **even** value upon commit, using the human-specified Law 1 memory ordering (`RT-01`).
  - The 500 Hz reader reads `seq_before`, copies the cache-line-aligned payload, and reads `seq_after`. If `seq_before != seq_after` or `seq_before % 2 != 0`, the read is torn and immediately discarded without spinning/blocking.
- **Horizon TTL & Mode Degradation (`SafetyNoCollision`, `CBFBarrierInvariant`):**
  - Every action chunk and peer lease carries an integer tick TTL (`shm_chunk_ttl`, `peer_lease_ttl`, `ctrl_ttl` in `u16`/`u32`/`u64` ticks — never floats).
  - On each 500 Hz tick:
    - **`NOMINAL`**: fresh valid Seqlock frame with `shm_chunk_ttl > 1`, or cached horizon with `ctrl_ttl > 2` (decremented by 1 each tick), projected onto the safe velocity set via the CBF-QP shield.
    - **`DECEL_FALLBACK`**: when `shm_chunk_ttl == 1` or `ctrl_ttl == 2`, command deterministic deceleration toward zero while satisfying the CBF braking-distance barrier (`robot_pos + v + BrakingDistance(v) <= EffectiveObstaclePos`).
    - **`STANCE_LOCK`**: when `ctrl_ttl <= 1` without a fresh valid frame, or upon any safety/validation failure, set `ctrl_ttl = 0`, `ctrl_mode = StanceLock`, and `ctrl_vel = 0` immediately.

### Numerical Determinism & Solver Bounds (RT-08)
- **Boundary sanitization:** Every floating-point value (`f32`/`f64`) entering from sensors, `vrka_proposer`, `vrka-swarm`, or `vrka-sim` must be checked with `.is_finite()` (`!x.is_nan() && !x.is_infinite()`). Any `NaN` or `Inf` immediately rejects the frame and triggers `DECEL_FALLBACK` / `STANCE_LOCK`.
- **Integer domain types:** Sequence numbers (`shm_seq`), epochs (`shm_threat_epoch`), tick TTLs (`shm_chunk_ttl`, `ctrl_ttl`, `peer_lease_ttl`), and timestamps (`timestamp_ns`) must use fixed-width unsigned integers (`u64`, `u32`, `u16`). Using `f32`/`f64` for counters, ticks, or time is a `BLOCK` violation.
- **Bounded QP iterations:** Any numerical solver in `vrka-cbf` must execute a fixed, compile-time-bounded maximum number of iterations using pre-allocated stack/arena matrices. If the solver does not converge within the tick budget or becomes infeasible, fall back deterministically to the verified braking deceleration / `STANCE_LOCK` command.
- **Deterministic replay (RT-19):** Every mode transition, CBF safety shield clamp, and lease expiration writes an immutable binary flight-recorder entry containing the monotonic tick, sequence number, threat epoch, input candidate command, and shielded output command.

## 4. Hardware, Memory & OS Isolation (RT-02, RT-03, RT-15, RT-20)

### Cache-Line ABI & Zero Padding (RT-03)
- Hardware cache lines are `CACHE_LINE_BYTES = 64` bytes. To prevent false sharing between the 20–25 Hz writer core and the 500 Hz reader core, all shared headers and slots must be `#[repr(C, align(64))]` with size equal to a non-zero multiple of 64 bytes, verified via `assert_cache_line_aligned!(Type, SIZE)`.
- All padding bytes must be explicitly declared (e.g. `pub reserved: [u8; 56]`) and zero-initialized (`const fn new_zeroed()`) so no uninitialized padding bytes ever cross shared memory or network boundaries.

### C-FFI & Supply-Chain Isolation (RT-15)
- C-FFI dependencies (`libmujoco`, `osqp`, `libc`, `io_uring`) are restricted to their owning adapter crates (`vrka-sim`, cold-path `vrka-shm` setup, `vrka-rt`, `vrka-swarm`) and must never leak raw pointers (`*const T`, `*mut T`) or C types into domain APIs.
- Wrap every C resource in a safe Rust type with deterministic cleanup (`Drop`) on the cold path and pre-allocated arenas on the hot path.
- `deny.toml` enforces `multiple-versions = "deny"` to prevent duplicate `*-sys` C symbol linkages.

### Linux `PREEMPT_RT` & Memory Locking (RT-20)
- Before entering the 500 Hz spine loop, `vrka-rt` and `vrka-swarm` must:
  1. Allocate all shared-memory mappings, `io_uring` rings, and telemetry buffers.
  2. Lock all current and future virtual memory pages into physical RAM via `mlockall(MCL_CURRENT | MCL_FUTURE)` so zero page faults occur during real-time execution.
  3. Pin the 500 Hz thread to an isolated CPU core (`sched_setaffinity`) and configure real-time scheduling (`SCHED_FIFO` or `SCHED_DEADLINE`).

## 5. Time & Synchronization (RT-16)

- **Monotonic clock only on the hot path.** Represent all real-time control deadlines, scheduling periods, and jitter measurements as `u64` nanoseconds from `CLOCK_MONOTONIC_RAW` (or hardware PTP clock). Never call `SystemTime::now()`, `Instant::now()`, or `datetime.now()` inside pure control functions — inject the monotonic timestamp (`now_ns: u64` or `tick: u64`) explicitly at the tick boundary (`RT-10`).
- **Multi-agent swarm time (`vrka-swarm`).** Cross-robot peer leases synchronize via IEEE 1588 PTPv2 hardware timestamps (`u64` nanoseconds + epoch). A peer packet whose timestamp or epoch falls outside the configured drift window is rejected as stale (`RT-07`, `RT-17`).
- **Cold-path logs.** Only cold-path supervisor and Python proposer logs attach an RFC 3339 UTC wall-clock timestamp alongside the monotonic `timestamp_ns` and `shm_seq`.

## 6. Spatial Security & Fault Resilience (RT-08, RT-17, RT-18)

- **Authenticated peer leases (RT-17).** Deny by default on the swarm network boundary. Every incoming `vrka-swarm` UDP lease frame must be validated for packet length, protocol version, monotonic sequence number (anti-replay), spatial bounds (`0..=MAX_CORRIDOR_POS`), positive TTL (`1..=MAX_HORIZON_TTL`), and cryptographic MAC / spatial security token before updating `peer_pos` and `peer_lease_ttl`.
- **Parse, don't transmute (RT-08).** Validate wire and shared-memory frames at ingestion. Never `core::mem::transmute` raw network bytes into Rust enums or booleans (which causes instant Undefined Behavior on invalid discriminants). Decode fixed-width primitives and validate ranges explicitly.
- **Non-blocking `io_uring` & zero hot-path retries (RT-18).** All network and IPC I/O on the real-time path uses pre-registered buffers (`IORING_REGISTER_BUFFERS`) and non-blocking completion polling (`io_uring_peek_cqe`). Never block or retry a failed/timed-out I/O operation inside a 500 Hz tick — record the miss, decrement `ctrl_ttl` / `peer_lease_ttl`, and let the horizon watchdog govern degradation.

## 7. Real-Time Observability & Black-Box Flight Recorder (RT-12, RT-19)

- **Zero-allocation hot-path telemetry (RT-12).** Formatting strings (`core::fmt`, `format!`, `println!`, `tracing` string macros) and synchronous file/console writes are strictly forbidden in the 500 Hz loop.
- **Binary ring buffer & eBPF (`vrka-ebpf`).** The 500 Hz spine writes fixed-size `#[repr(C, align(64))]` POD telemetry records (`tick`, `timestamp_ns`, `ctrl_mode`, `shm_seq`, `ctrl_ttl`, `ctrl_vel`, `robot_pos`, `peer_lease_ttl`, `jitter_ns`) into a wait-free ring buffer consumed by a cold-path background thread, supplemented by `aya-rs` eBPF kernel scheduling probes (`MAX_JITTER_BUDGET_NS = 50_000`).
- **Cold-path structured JSON (`proposer/` & startup).** Cold-path components emit structured JSON logs with `timestamp` (RFC 3339 UTC), `timestamp_ns`, `level` (`INFO` for lifecycle/mode transitions, `WARN` for single-tick torn reads or peer drops, `ERROR` for invariant breaches or `STANCE_LOCK` trips), `component`, and `epoch`.

## 8. Verification Pyramid (RT-13)

- **Bug fixes:** write the reproducing test first, watch it fail, apply the minimal fix, and watch it pass.
- **Done means green:** never call a task complete without `make validate` (`fmt` + `clippy -D warnings` + `check_no_std.sh` + `cargo test --workspace` + `verify_specs.sh`) passing.
- **Zero-allocation proofs (`Law 2`):** every hot-path function is tested under `CountingAllocator` (`crates/vrka-abi/tests/zero_alloc_hot_path.rs`) proving `0` allocations and `0` bytes.
- **Edge & fault-injection cases:** `ctrl_ttl` countdown (`3 → 2 → 1 → 0`), torn Seqlock reads (`shm_seq` odd or changing mid-read), `NaN`/`Inf`/negative velocity inputs, peer lease sudden appearance/expiry, unaligned memory capacities, and `MAX_JITTER_BUDGET_NS` overrun.
- **Formal & property-based verification:** headless TLA+/PlusCal model checking (`./scripts/verify_specs.sh`) for concurrency and horizon-lease state machines; property-based testing (`proptest` / `hypothesis`) or Kani/Miri verification for `unsafe` pointer math, Seqlock framing, and CBF kinematics.

## 9. Language Rules

### Rust (`crates/*`)
- **Toolchain & Lints:** Rust 2021 (`1.93` in `rust-toolchain.toml`). Workspace denies `unsafe_op_in_unsafe_fn`, `clippy::undocumented_unsafe_blocks`, `clippy::unwrap_used`, `clippy::expect_used`, `clippy::panic`, and `-D warnings` on all targets. Never add `#[allow(...)]` (`RT-09`).
- **`#![no_std]` Purity:** `vrka-abi`, `vrka-cbf`, and `vrka-ebpf` are unconditionally `#![no_std]`. `vrka-shm` uses `#![cfg_attr(not(feature = "std"), no_std)]`. Verified by `./scripts/check_no_std.sh`.
- **`unsafe` Contract (`RT-09`):** Every `unsafe fn` has a `# Safety` doc comment; every `unsafe { ... }` block and `unsafe impl` has an immediately preceding `// SAFETY:` comment stating the exact pointer validity, 64-byte alignment, aliasing, initialized bit-pattern, and concurrency invariant.
- **Types & Functions:** Derive `Clone, Copy, Debug, PartialEq, Eq` on ABI/control types; mark pure constructors and getters `#[must_use]` and `const fn` wherever possible; return explicit `#![no_std]` error/status enums (`Result<T, VrkaError>`).

### TLA+ & PlusCal (`specs/*`)
- **Law 1 Protected (`RT-01`):** Agents never author or edit `.tla` or `.cfg` files without explicit human specification.
- **Translation & Model Checking:** Every `.tla` file containing a `--algorithm` block is translated via `pcal.trans` and checked with `tlc2.TLC -workers auto` via `./scripts/verify_specs.sh` (`make verify-specs`). Zero deadlocks and 100% invariant pass (`SafetyNoCollision`, `CBFBarrierInvariant`, `SeqlockNoTornRead`) are mandatory.

### Python (`proposer/*`)
- **Typing & Linting:** Python `>=3.11`, `mypy --strict`, and `ruff check` / `ruff format --check` (all rules in `proposer/pyproject.toml`, including `ANN`, `S`, `BLE`, `FBT`, `DTZ`, `T20`, `PT`, `PL`, `PERF`, `RUF`) enforced via `make check-python`.
- **Immutability & Validation:** Use `@dataclass(frozen=True, slots=True)` and `tuple` over `list`. Validate all tensor/array shapes, finite floats (`math.isfinite`), and integer TTL bounds (`1 <= ttl <= MAX_HORIZON_TTL`) before writing to shared memory.
- **Forbidden Constructs:** No `# type: ignore`, `# noqa`, `Any`, `print()`, `datetime.now()` without `tz=timezone.utc`, or bare `except:`. Manage dependencies exclusively with `uv` (`uv.lock`).

### C / C++ & eBPF Boundaries (`vrka-sim`, `vrka-ebpf`)
- **C-FFI (`vrka-sim`):** Pin header/library versions; validate every pointer returned from C against `null` before dereferencing; isolate `unsafe extern "C"` calls inside thin adapter functions with `// SAFETY:` proofs; check struct layouts with compile-time `size_of`/`align_of`/`offset_of!` assertions (`RT-03`).
- **eBPF (`vrka-ebpf`):** Strictly `#![no_std]`, bounded loops only (verifier-safe), stack frame `≤ 512` bytes, zero map lookups without explicit `Option` handling.
