//! Deterministic 500 Hz real-time control spine state machine and watchdog.

use vrka_abi::{ActionChunkSlot, FlightRecorderEntry, VrkaError};

/// 500 Hz control spine operational mode.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CtrlMode {
    /// Active valid horizon lease with forward-invariant trajectory tracking.
    Nominal = 0,
    /// Approaching lease expiry; deterministic deceleration ladder active.
    DecelFallback = 1,
    /// Lease expired or safety fault; zero velocity stance locked.
    StanceLock = 2,
}

/// State of the 500 Hz real-time control spine.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RtSpineState {
    /// Monotonic control tick counter.
    pub tick: u64,
    /// Active control mode.
    pub mode: CtrlMode,
    /// Active horizon lease TTL in ticks.
    pub ctrl_ttl: u16,
    /// Commanded velocity in meters per second.
    pub ctrl_vel: f32,
    /// Current estimated robot position.
    pub robot_pos: f32,
    /// Current effective obstacle position.
    pub effective_obstacle_pos: f32,
}

impl Default for RtSpineState {
    fn default() -> Self {
        Self::new()
    }
}

impl RtSpineState {
    /// Creates an initial stance-locked spine state.
    #[must_use]
    pub const fn new() -> Self {
        Self {
            tick: 0,
            mode: CtrlMode::StanceLock,
            ctrl_ttl: 0,
            ctrl_vel: 0.0,
            robot_pos: 0.0,
            effective_obstacle_pos: 7.0,
        }
    }
}

/// 500 Hz real-time daemon supervisor stub.
pub struct RtSpine {
    state: RtSpineState,
}

impl Default for RtSpine {
    fn default() -> Self {
        Self::new()
    }
}

impl RtSpine {
    /// Creates a new spine instance in stance lock.
    #[must_use]
    pub const fn new() -> Self {
        Self {
            state: RtSpineState::new(),
        }
    }

    /// Returns the current spine state.
    #[must_use]
    pub const fn state(&self) -> &RtSpineState {
        &self.state
    }

    /// Steps the 500 Hz control loop for a single tick (stub).
    ///
    /// # Errors
    /// Returns [`VrkaError::NotImplemented`].
    pub fn step_tick(
        &mut self,
        now_ns: u64,
        fresh_read: Option<&ActionChunkSlot>,
    ) -> Result<FlightRecorderEntry, VrkaError> {
        let _ = (now_ns, fresh_read);
        Err(VrkaError::NotImplemented)
    }
}
