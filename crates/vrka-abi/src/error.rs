//! `#![no_std]` error types for `vrka-vla` ABI, Seqlock, and safety shield boundaries.

/// Primary error enum for `vrka-vla` real-time execution.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VrkaError {
    /// Placeholder error for unimplemented operations.
    NotImplemented,
    /// Torn Seqlock read (in-flight write or sequence mismatch).
    TornRead,
    /// Shared-memory buffer or capacity is not 64-byte cache-line aligned.
    UnalignedBuffer,
    /// Velocity is non-finite (NaN or infinite) or exceeds physical limits.
    InvalidVelocity,
    /// Horizon TTL is zero or exceeds maximum permitted lease duration.
    InvalidTtl,
    /// Monotonic sequence number or epoch rolled backward or is inconsistent.
    InvalidSequence,
    /// Peer lease has expired or failed `PTPv2` drift verification.
    StaleLease,
    /// Provided buffer capacity is too small for the requested operation.
    BufferTooSmall,
    /// Forward invariance or CBF safety barrier constraint violated.
    SafetyViolation,
}
