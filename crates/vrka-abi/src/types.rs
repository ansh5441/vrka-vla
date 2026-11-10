//! Cache-line-aligned ABI frame headers, trajectory slots, and telemetry types.

use crate::assert_cache_line_aligned;

/// 64-byte cache-line-aligned shared-memory slot header.
#[repr(C, align(64))]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ShmSlotHeader {
    /// Monotonic sequence counter (odd = write in progress; even = committed).
    pub sequence: u64,
    /// Threat epoch matching the current horizon lease context.
    pub epoch: u64,
    /// Monotonic write timestamp in nanoseconds.
    pub timestamp_ns: u64,
    /// Status and capability flags.
    pub flags: u32,
    /// Explicit zeroed padding to round to a 64-byte cache line.
    pub reserved: [u8; 36],
}

assert_cache_line_aligned!(ShmSlotHeader, 64);

impl ShmSlotHeader {
    /// Creates a zeroed slot header without heap allocation.
    #[must_use]
    pub const fn new_zeroed() -> Self {
        Self {
            sequence: 0,
            epoch: 0,
            timestamp_ns: 0,
            flags: 0,
            reserved: [0u8; 36],
        }
    }
}

/// 128-byte cache-line-aligned action chunk slot exchanged via Seqlock IPC.
#[repr(C, align(64))]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ActionChunkSlot {
    /// Embedded 64-byte slot header.
    pub header: ShmSlotHeader,
    /// Horizon lease time-to-live in 500 Hz ticks.
    pub chunk_ttl: u16,
    /// Padding byte alignment reservation.
    pub reserved0: [u8; 2],
    /// Proposed command velocity in meters per second.
    pub cmd_vel: f32,
    /// Explicit zeroed padding to round to 128 bytes (2 cache lines).
    pub reserved1: [u8; 56],
}

assert_cache_line_aligned!(ActionChunkSlot, 128);

impl ActionChunkSlot {
    /// Creates a zeroed action chunk slot without heap allocation.
    #[must_use]
    pub const fn new_zeroed() -> Self {
        Self {
            header: ShmSlotHeader::new_zeroed(),
            chunk_ttl: 0,
            reserved0: [0u8; 2],
            cmd_vel: 0.0,
            reserved1: [0u8; 56],
        }
    }

    /// Validates numerical and TTL boundary conditions on the slot.
    #[must_use]
    pub fn is_valid(&self) -> bool {
        self.cmd_vel.is_finite() && self.cmd_vel >= 0.0 && self.chunk_ttl > 0
    }
}

/// 64-byte cache-line-aligned spatial security token for peer lease authentication.
#[repr(C, align(64))]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SpatialSecurityToken {
    /// Unique identifier for the token instance.
    pub token_id: u64,
    /// Monotonic threat epoch of the token.
    pub epoch: u64,
    /// Token expiry deadline in monotonic nanoseconds.
    pub valid_until_ns: u64,
    /// Cryptographic message authentication code over spatial payload.
    pub mac: [u8; 32],
    /// Reserved alignment padding.
    pub reserved: [u8; 8],
}

assert_cache_line_aligned!(SpatialSecurityToken, 64);

impl SpatialSecurityToken {
    /// Creates a zeroed security token.
    #[must_use]
    pub const fn new_zeroed() -> Self {
        Self {
            token_id: 0,
            epoch: 0,
            valid_until_ns: 0,
            mac: [0u8; 32],
            reserved: [0u8; 8],
        }
    }
}

/// 64-byte cache-line-aligned black-box flight recorder telemetry entry.
#[repr(C, align(64))]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FlightRecorderEntry {
    /// Monotonic 500 Hz control spine tick.
    pub tick: u64,
    /// Monotonic timestamp in nanoseconds.
    pub timestamp_ns: u64,
    /// Monotonic Seqlock sequence number at tick boundary.
    pub shm_seq: u64,
    /// Measured wakeup jitter in nanoseconds.
    pub jitter_ns: u64,
    /// Shielded control velocity output.
    pub ctrl_vel: f32,
    /// Estimated 1D robot position.
    pub robot_pos: f32,
    /// Active horizon lease TTL.
    pub ctrl_ttl: u16,
    /// Active peer obstacle lease TTL.
    pub peer_lease_ttl: u16,
    /// Active control mode (0: Nominal, 1: `DecelFallback`, 2: `StanceLock`).
    pub ctrl_mode: u8,
    /// Padding alignment bytes.
    pub reserved0: [u8; 3],
    /// Reserved trailing padding to complete 64-byte cache line.
    pub reserved1: [u8; 16],
}

assert_cache_line_aligned!(FlightRecorderEntry, 64);

impl FlightRecorderEntry {
    /// Creates a zeroed flight recorder entry.
    #[must_use]
    pub const fn new_zeroed() -> Self {
        Self {
            tick: 0,
            timestamp_ns: 0,
            shm_seq: 0,
            jitter_ns: 0,
            ctrl_vel: 0.0,
            robot_pos: 0.0,
            ctrl_ttl: 0,
            peer_lease_ttl: 0,
            ctrl_mode: 0,
            reserved0: [0u8; 3],
            reserved1: [0u8; 16],
        }
    }
}
