//! `#![no_std]` stub crate for `aya-rs` kernel real-time scheduling and jitter probes.

#![no_std]

/// Maximum tolerated scheduling jitter in nanoseconds before an eBPF tracepoint alert is raised.
pub const MAX_JITTER_BUDGET_NS: u64 = 50_000;
