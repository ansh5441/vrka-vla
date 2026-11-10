//! Shared-memory IPC transport layer for `vrka-vla`.
//!
//! By default this crate compiles as `#![no_std]`. Enable the `std` Cargo feature only in
//! cold-path initialization binaries that map POSIX shared-memory segments via `mmap`.

#![cfg_attr(not(feature = "std"), no_std)]

use core::sync::atomic::{AtomicU64, Ordering};
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

/// Single-writer Seqlock IPC channel.
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
    /// Returns [`VrkaError::InvalidVelocity`] if chunk is invalid.
    pub fn write_chunk(&mut self, chunk: &ActionChunkSlot) -> Result<(), VrkaError> {
        if !chunk.is_valid() {
            return Err(VrkaError::InvalidVelocity);
        }

        // SAFETY: addr_of_mut produces a valid, aligned pointer to slot sequence.
        // u64 and AtomicU64 have identical size (8 bytes) and alignment.
        let seq_atomic =
            unsafe { &*(core::ptr::addr_of_mut!(self.slot.header.sequence).cast::<AtomicU64>()) };

        // WriteBegin: increment sequence to an odd value
        seq_atomic.fetch_add(1, Ordering::Release);

        self.slot.header.epoch = chunk.header.epoch;
        self.slot.header.timestamp_ns = chunk.header.timestamp_ns;
        self.slot.header.flags = chunk.header.flags;
        self.slot.chunk_ttl = chunk.chunk_ttl;
        self.slot.cmd_vel = chunk.cmd_vel;

        // WriteCommit: increment sequence to an even value
        seq_atomic.fetch_add(1, Ordering::Release);

        Ok(())
    }
}

/// Wait-free non-spinning Seqlock IPC reader.
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
    /// Returns [`VrkaError::TornRead`] on sequence mismatch or odd sequence, or [`VrkaError::InvalidTtl`].
    pub fn read_chunk(&self, out: &mut ActionChunkSlot) -> Result<(), VrkaError> {
        // SAFETY: addr_of produces a valid, aligned pointer to slot sequence.
        // u64 and AtomicU64 have identical size (8 bytes) and alignment.
        let seq_atomic =
            unsafe { &*(core::ptr::addr_of!(self.slot.header.sequence).cast::<AtomicU64>()) };

        let seq_before = seq_atomic.load(Ordering::Acquire);
        if seq_before % 2 != 0 {
            return Err(VrkaError::TornRead);
        }

        out.header.sequence = seq_before;
        out.header.epoch = self.slot.header.epoch;
        out.header.timestamp_ns = self.slot.header.timestamp_ns;
        out.header.flags = self.slot.header.flags;
        out.chunk_ttl = self.slot.chunk_ttl;
        out.cmd_vel = self.slot.cmd_vel;

        let seq_after = seq_atomic.load(Ordering::Acquire);
        if seq_before != seq_after {
            return Err(VrkaError::TornRead);
        }

        if out.chunk_ttl == 0 {
            return Err(VrkaError::InvalidTtl);
        }

        Ok(())
    }
}
