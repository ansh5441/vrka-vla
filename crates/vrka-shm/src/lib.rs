//! Shared-memory IPC transport layer for `vrka-vla`.
//!
//! By default this crate compiles as `#![no_std]`. Enable the `std` Cargo feature only in
//! cold-path initialization binaries that map POSIX shared-memory segments via `mmap`.
//! Seqlock synchronization algorithms are intentionally omitted from this scaffold (Law 1).

#![cfg_attr(not(feature = "std"), no_std)]

pub use vrka_abi::CACHE_LINE_BYTES;

/// Placeholder configuration descriptor for a shared-memory region.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ShmRegionDescriptor {
    /// Total byte capacity of the shared memory region (must be a multiple of [`CACHE_LINE_BYTES`]).
    pub capacity_bytes: usize,
}

impl ShmRegionDescriptor {
    /// Returns `true` if `capacity_bytes` is non-zero and cache-line aligned.
    #[must_use]
    pub const fn is_aligned(&self) -> bool {
        self.capacity_bytes > 0 && self.capacity_bytes.is_multiple_of(CACHE_LINE_BYTES)
    }
}
