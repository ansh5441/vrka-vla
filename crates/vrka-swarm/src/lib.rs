//! Multi-agent pack lease coordination and non-blocking peer broadcast library.

use vrka_abi::{assert_cache_line_aligned, SpatialSecurityToken, VrkaError};

/// Nominal peer lease broadcast port across the wolf-pack fleet.
pub const DEFAULT_SWARM_PORT: u16 = 9500;

/// Default static threat boundary in meters.
pub const DEFAULT_THREAT_POS: f32 = 7.0;

/// 128-byte cache-line-aligned peer lease UDP broadcast wire frame.
#[repr(C, align(64))]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct PeerLeaseFrame {
    /// Unique identifier for the transmitting peer robot.
    pub sender_id: u64,
    /// Monotonic frame sequence counter for anti-replay.
    pub sequence: u64,
    /// Monotonic `PTPv2` hardware timestamp in nanoseconds.
    pub timestamp_ns: u64,
    /// Estimated 1D position of the peer in the shared corridor.
    pub peer_pos: f32,
    /// Current velocity of the peer.
    pub peer_vel: f32,
    /// Lease time-to-live in 500 Hz ticks.
    pub peer_lease_ttl: u16,
    /// Sub-header alignment padding.
    pub reserved0: [u8; 6],
    /// Reserved padding to round to first 64-byte line.
    pub reserved1: [u8; 24],
    /// Embedded 64-byte spatial security token.
    pub token: SpatialSecurityToken,
}

assert_cache_line_aligned!(PeerLeaseFrame, 128);

impl PeerLeaseFrame {
    /// Creates a zeroed peer lease wire frame.
    #[must_use]
    pub const fn new_zeroed() -> Self {
        Self {
            sender_id: 0,
            sequence: 0,
            timestamp_ns: 0,
            peer_pos: 0.0,
            peer_vel: 0.0,
            peer_lease_ttl: 0,
            reserved0: [0u8; 6],
            reserved1: [0u8; 24],
            token: SpatialSecurityToken::new_zeroed(),
        }
    }

    /// Validates wire frame boundary conditions.
    #[must_use]
    pub fn is_valid(&self) -> bool {
        self.peer_pos.is_finite()
            && self.peer_vel.is_finite()
            && self.peer_pos >= 0.0
            && self.peer_lease_ttl > 0
    }
}

/// Swarm obstacle aggregator computing `EffectiveObstaclePos`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct PeerLeaseAggregator {
    active_peer_pos: f32,
    active_peer_lease_ttl: u16,
    static_threat_pos: f32,
}

impl Default for PeerLeaseAggregator {
    fn default() -> Self {
        Self::new(DEFAULT_THREAT_POS)
    }
}

impl PeerLeaseAggregator {
    /// Creates a new aggregator with the specified static threat boundary.
    #[must_use]
    pub const fn new(static_threat_pos: f32) -> Self {
        Self {
            active_peer_pos: static_threat_pos,
            active_peer_lease_ttl: 0,
            static_threat_pos,
        }
    }

    /// Evaluates `EffectiveObstaclePos` in accordance with ADR 005.
    #[must_use]
    pub fn effective_obstacle_pos(&self) -> f32 {
        if self.active_peer_lease_ttl > 0 && self.active_peer_pos < self.static_threat_pos {
            self.active_peer_pos
        } else {
            self.static_threat_pos
        }
    }

    /// Updates active peer obstacle reservation from a validated frame (stub).
    ///
    /// # Errors
    /// Returns [`VrkaError::InvalidVelocity`] if frame is invalid, or [`VrkaError::NotImplemented`].
    pub fn ingest_frame(&mut self, frame: &PeerLeaseFrame) -> Result<(), VrkaError> {
        if !frame.is_valid() {
            return Err(VrkaError::InvalidVelocity);
        }
        Err(VrkaError::NotImplemented)
    }

    /// Decrements active lease TTL on a 500 Hz tick drop (stub).
    pub fn step_tick(&mut self) {
        if self.active_peer_lease_ttl > 0 {
            self.active_peer_lease_ttl = self.active_peer_lease_ttl.saturating_sub(1);
        }
    }
}
