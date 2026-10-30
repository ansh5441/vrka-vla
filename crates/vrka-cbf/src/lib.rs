//! `#![no_std]` Control Barrier Function (CBF) safety shield crate stub.
//!
//! Barrier formulations and QP math are intentionally omitted from this scaffold (Law 1).

#![no_std]

pub use vrka_abi::CACHE_LINE_BYTES;

/// Placeholder status code returned by the CBF safety filter stub.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ShieldStatus {
    /// Stub status indicating the safety filter has not yet been initialized with barrier equations.
    UninitializedStub,
}
