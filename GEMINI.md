# `vrka-vla` — Immutable Architectural Laws for Autonomous & Pair-Programming Agents

> This file mirrors [`AGENTS.md`](./AGENTS.md) so both Gemini and multi-agent toolchains load identical architectural constraints at session start.

**Project:** `vrka-vla` (*The Vedic Wolf Pack: Deterministic Real-Time Execution & Safety Architecture for Embodied Physical AI*)  
**Enforcement Status:** Mandatory, Non-Negotiable, Active from Commit Zero.

---

## The Three Immutable Laws

### Law 1: Human-Only Authority over Memory Ordering, Formal Invariants, and Barrier Math
> **The coding agent must never author or modify atomic memory ordering (`Ordering::Acquire`, `Ordering::Release`, `Ordering::AcqRel`, `Ordering::SeqCst`, `Ordering::Relaxed` on synchronization primitives), TLA+ / PlusCal safety and liveness invariants (`specs/`), or Control Barrier Function (CBF-QP) barrier equations (`crates/vrka-cbf`) without explicit human specification.**

- **Scope:**
  - Wait-free Seqlock protocols and shared-memory fences in `crates/vrka-shm` and `crates/vrka-abi`.
  - Formal `.tla` and `.cfg` state machines in `specs/horizon_lease/` and `specs/pack_swarm/`.
  - Lie derivatives, class-$\mathcal{K}$ functions, and QP safety shield constraints in `crates/vrka-cbf`.
- **Agent Protocol:** If a task requires introducing or altering any of these constructs and the human has not provided the exact mathematical or memory-ordering specification, **stop immediately and request the specification from the human architect**.

### Law 2: Zero Dynamic Heap Allocation in the 500 Hz Execution Loop
> **Zero dynamic heap allocation is permitted inside the 500 Hz real-time execution loop after startup initialization.**

- **Scope:**
  - `crates/vrka-abi`, `crates/vrka-shm` (default feature set), and `crates/vrka-cbf` are strictly `#![no_std]` and must never link `alloc` or `std` on the hot path.
  - Within `crates/vrka-rt` and `crates/vrka-swarm`, all buffers, arena slabs, `io_uring` submission/completion rings, and solver workspaces must be pre-allocated and locked into physical RAM (`mlockall(MCL_CURRENT | MCL_FUTURE)`) prior to entering the 500 Hz control loop.
  - Every hot-path routine must be covered by a `CountingAllocator` integration test (modeled on `crates/vrka-abi/tests/zero_alloc_hot_path.rs`) proving `alloc_count == 0`.

### Law 3: Compile-Time Size & Alignment Assertions on Every ABI / FFI Boundary
> **Every FFI boundary or `#[repr(C, align(64))]` struct must have a corresponding compile-time size and alignment assertion.**

- **Scope:**
  - All shared-memory frame headers, trajectory chunks, spatial security tokens, and C-FFI structs in `crates/vrka-abi`, `crates/vrka-shm`, `crates/vrka-cbf`, and `crates/vrka-sim`.
  - Use `vrka_abi::assert_cache_line_aligned!(StructName, EXPECTED_BYTE_SIZE)` (or an explicit `const _: () = assert!(...)` check for non-64-byte C-FFI descriptors) immediately adjacent to the type definition so false sharing and ABI drift fail compilation.

---

## Static Hygiene & Toolchain Gates

1. **Zero Undocumented `unsafe`:**
   - Workspace lints enforce `unsafe_op_in_unsafe_fn = "deny"` and `clippy::undocumented_unsafe_blocks = "deny"`.
   - Every `unsafe` block must be preceded by a `// SAFETY:` comment stating the exact pointer validity, aliasing, alignment, and concurrency invariant that holds.
2. **Panic-Free 500 Hz Spine:**
   - Workspace lints enforce `clippy::unwrap_used = "deny"`, `clippy::expect_used = "deny"`, and `clippy::panic = "deny"`.
   - All fallible operations must return explicit typed results or trigger deterministic safe-stop transitions.
3. **Canonical Verification Interface:**
   - Run `make init-hooks` once after cloning to activate `.githooks/pre-commit` and `.githooks/pre-push`.
   - Run `make validate` to execute `cargo fmt`, `cargo clippy`, `scripts/check_no_std.sh`, `cargo test --workspace`, and `scripts/verify_specs.sh`.
