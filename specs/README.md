# `vrka-vla` Formal Specifications — PlusCal & TLA+ Quick-Reference Cheat Sheet

A 1-page field guide to **PlusCal (p-syntax)** and **TLA+** for Go and Rust systems engineers authoring formal state machines in `specs/`.

---

## 1. Assignment (`:=`) vs. Equality (`=`) vs. Definition (`==`)

| Operator | Context | Meaning | Rust / Go Analogy |
| :--- | :--- | :--- | :--- |
| `:=` | PlusCal statement | Mutates a state variable in the next step (`x' = ...` in generated TLA+). | `x = val;` |
| `=` | Expression / Predicate | Boolean equality comparison (evaluates to `TRUE` or `FALSE`). | `x == val` |
| `==` | `define` block / TLA+ | Immutable operator or invariant definition (zero-cost macro/function). | `fn inv(x: i64) -> bool` |

```tla
define
    MaxBrake(v) == v * 2              \* Operator definition (==)
    IsStopped   == ctrl_vel = 0       \* Boolean equality test (=) inside definition (==)
end define;

UpdateStep:
    ctrl_vel := 0;                    \* State mutation (:=)
```

---

## 2. Non-Deterministic Choice (`with` & `either`)

Model checking explores **every** possible branch rather than sampling randomly.

- **Set choice (`with x \in S do ... end with;`)**: TLC branches the state graph for every element `x` in set `S` inside a single atomic step.
  ```tla
  ProposeChunk:
      with v \in 0..MAX_VEL, ttl \in 1..MAX_HORIZON_TTL do
          shm_cmd_vel := v;
          shm_chunk_ttl := ttl;
      end with;
  ```
- **Branch choice (`either ... or ... end either;`)**: Non-deterministically selects one execution path (e.g., UDP packet delivered vs. dropped).
  ```tla
  NetworkStep:
      either
          peer_lease_ttl := MAX_HORIZON_TTL;
      or
          skip; \* Packet lost in flight
      end either;
  ```

---

## 3. Atomic Step Labels (`LabelName:`)

In PlusCal, **labels define the grain of atomicity** (interleaving points between concurrent processes):
- Everything between one label and the next executes in a **single indivisible TLA+ transition** (`pc = "LabelName"`).
- **Mandatory label placement rules** (`pcal.trans` rejects violations):
  1. The first statement of every `process` body (`begin`) and `while` loop body must be labeled.
  2. Any statement immediately following a `while`, `if`, `either`, `goto`, or `return` must be labeled if control flow merges or loops.
  3. The same variable cannot be assigned (`:=`) twice within the same label—split across two labels (e.g., `WriteBegin:` then `WriteCommit:` for a Seqlock).

---

## 4. Guard Conditions (`await` / `when`)

`await Cond;` (synonym: `when Cond;`) is a **transition guard**, not a spinning loop:
- An atomic step containing `await Cond;` is **enabled** only in states where `Cond` is `TRUE`.
- If `Cond` is `FALSE`, TLC simply does not schedule that process on this step (zero state-space explosion from busy-waiting).

```tla
ReadConsistent:
    await shm_seq % 2 = 0;            \* Step enabled only when writer is not mid-update (even seq)
    ctrl_vel := shm_cmd_vel;
```

---

## 5. TLA+ Logical & Set Operators (for `define` Invariants)

| TLA+ Syntax | Meaning | Notes |
| :--- | :--- | :--- |
| `P => Q` | Logical implication ("if `P` then `Q`") | Equivalent to `~P \/ Q`. Core building block for state invariants. |
| `/\` and `\/` | Logical AND (`&&`) and OR (`\|\|`) | Supports bulleted vertical lists aligned by column in TLA+. |
| `~P` | Logical NOT (`!P`) | Negation of predicate `P`. |
| `#` or `/=` | Not equal (`!=`) | e.g., `ctrl_mode # "NOMINAL"`. |
| `x \in S` | Set membership | `x \notin S` for non-membership; `a..b` for integer range `{a, ..., b}`. |
| `\A x \in S : P` | Universal quantifier ($\forall$) | `TRUE` iff `P` holds for every `x` in `S`. |
| `\E x \in S : P` | Existential quantifier ($\exists$) | `TRUE` iff `P` holds for at least one `x` in `S`. |

```tla
define
    \* Invariant: Whenever TTL expires, controller must not remain in NOMINAL mode
    LeaseExpirySafety == (ctrl_ttl = 0) => (ctrl_mode # "NOMINAL")
end define;
```

---

## 6. CLI Commands: PlusCal Translation & Headless TLC

Always run via the canonical Makefile or verification script (auto-bootstraps `specs/tools/tla2tools.jar`, which is git-ignored):

```bash
# 1. Canonical Makefile target for the Horizon Lease spec
make tla-check

# 2. Verify a single spec or all specs under specs/
./scripts/verify_specs.sh vrka_horizon_lease
./scripts/verify_specs.sh

# 3. Direct invocations (under the hood of verify_specs.sh)
java -XX:+UseParallelGC -cp specs/tools/tla2tools.jar pcal.trans specs/horizon_lease/vrka_horizon_lease.tla
java -XX:+UseParallelGC -cp specs/tools/tla2tools.jar tlc2.TLC -workers auto -cleanup -metadir /tmp/tlc \
    -config specs/horizon_lease/vrka_horizon_lease.cfg specs/horizon_lease/vrka_horizon_lease.tla
```
