//! `#![no_std]` ABI layout contracts and compile-time alignment assertions for `vrka-vla`.
//!
//! Domain business logic, Seqlock payloads, and spatial token layouts are authored by humans.
//! Every `#[repr(C, align(64))]` structure in this crate must invoke [`assert_cache_line_aligned!`]
//! in accordance with Architectural Law 3.

#![no_std]

pub mod error;
pub mod types;

pub use error::VrkaError;
pub use types::{ActionChunkSlot, FlightRecorderEntry, ShmSlotHeader, SpatialSecurityToken};

/// Hardware cache-line size in bytes across supported target architectures.
pub const CACHE_LINE_BYTES: usize = 64;

/// Compile-time static assertion verifying that `$ty` has an exact alignment of
/// [`CACHE_LINE_BYTES`] (64 bytes) and a total size that is a non-zero multiple of 64 bytes.
#[macro_export]
macro_rules! assert_cache_line_aligned {
    ($ty:ty, $expected_size:expr) => {
        const _: () = {
            assert!(
                core::mem::align_of::<$ty>() == $crate::CACHE_LINE_BYTES,
                "ABI violation (Law 3): struct alignment must equal 64 bytes (CACHE_LINE_BYTES)"
            );
            assert!(
                core::mem::size_of::<$ty>() == $expected_size,
                "ABI violation (Law 3): struct size does not match expected size"
            );
            assert!(
                core::mem::size_of::<$ty>() > 0
                    && core::mem::size_of::<$ty>().is_multiple_of($crate::CACHE_LINE_BYTES),
                "ABI violation (Law 3): struct size must be a non-zero multiple of 64 bytes"
            );
        };
    };
}

/// Placeholder 64-byte cache-line-aligned ABI frame header demonstrating Law 3 enforcement.
#[repr(C, align(64))]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CacheLineSlotPlaceholder {
    /// Monotonic frame sequence slot (placeholder; Seqlock logic authored separately).
    pub sequence_slot: u64,
    /// Reserved padding to fill a single 64-byte hardware cache line.
    pub reserved: [u8; 56],
}

assert_cache_line_aligned!(CacheLineSlotPlaceholder, 64);

impl CacheLineSlotPlaceholder {
    /// Creates a zeroed placeholder slot without heap allocation.
    #[must_use]
    pub const fn new_zeroed() -> Self {
        Self {
            sequence_slot: 0,
            reserved: [0u8; 56],
        }
    }
}
