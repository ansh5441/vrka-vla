//! Shared-memory IPC transport layer for `vrka-vla`.
//!
//! By default this crate compiles as `#![no_std]`. Enable the `std` Cargo feature only in
//! cold-path initialization binaries that map POSIX shared-memory segments via `mmap`.

#![cfg_attr(not(feature = "std"), no_std)]

pub use vrka_abi::{ActionChunkSlot, ShmSlotHeader, VrkaError, CACHE_LINE_BYTES};

/// Configuration descriptor for a shared-memory region.
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

/// Single-writer Seqlock IPC channel stub.
pub struct SeqlockWriter<'a> {
    slot: &'a mut ActionChunkSlot,
}

impl<'a> SeqlockWriter<'a> {
    /// Creates a writer wrapping a mutable action chunk slot.
    #[must_use]
    pub fn new(slot: &'a mut ActionChunkSlot) -> Self {
        Self { slot }
    }

    /// Writes an action chunk into the shared memory slot.
    ///
    /// # Errors
    /// Returns [`VrkaError::InvalidVelocity`] if chunk is invalid, or [`VrkaError::NotImplemented`].
    pub fn write_chunk(&mut self, chunk: &ActionChunkSlot) -> Result<(), VrkaError> {
        if !chunk.is_valid() {
            return Err(VrkaError::InvalidVelocity);
        }
        let _ = self.slot;
        Err(VrkaError::NotImplemented)
    }
}

/// Wait-free non-spinning Seqlock IPC reader stub.
pub struct SeqlockReader<'a> {
    slot: &'a ActionChunkSlot,
}

impl<'a> SeqlockReader<'a> {
    /// Creates a reader wrapping a shared action chunk slot.
    #[must_use]
    pub const fn new(slot: &'a ActionChunkSlot) -> Self {
        Self { slot }
    }

    /// Reads an action chunk from shared memory without spinning.
    ///
    /// # Errors
    /// Returns [`VrkaError::TornRead`] on sequence mismatch, or [`VrkaError::NotImplemented`].
    pub fn read_chunk(&self, out: &mut ActionChunkSlot) -> Result<(), VrkaError> {
        let _ = (self.slot, out);
        Err(VrkaError::NotImplemented)
    }
}
