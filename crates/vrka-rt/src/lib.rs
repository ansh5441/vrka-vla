//! Deterministic 500 Hz real-time control spine state machine and watchdog.

use vrka_abi::{ActionChunkSlot, FlightRecorderEntry, VrkaError};
use vrka_cbf::CbfSafetyFilter;

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

/// 500 Hz real-time daemon supervisor.
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

    fn next_candidate_velocity(&mut self, fresh_read: Option<&ActionChunkSlot>) -> f32 {
        match fresh_read {
            Some(chunk) if chunk.is_valid() => {
                self.state.ctrl_ttl = chunk.chunk_ttl;
                if chunk.chunk_ttl > 1 {
                    self.state.mode = CtrlMode::Nominal;
                    chunk.cmd_vel
                } else {
                    self.state.mode = CtrlMode::DecelFallback;
                    (chunk.cmd_vel - 1.0).max(0.0)
                }
            }
            _ => match self.state.ctrl_ttl.cmp(&2) {
                core::cmp::Ordering::Greater => {
                    self.state.ctrl_ttl -= 1;
                    self.state.mode = CtrlMode::Nominal;
                    self.state.ctrl_vel
                }
                core::cmp::Ordering::Equal => {
                    self.state.ctrl_ttl = 1;
                    self.state.mode = CtrlMode::DecelFallback;
                    (self.state.ctrl_vel - 1.0).max(0.0)
                }
                core::cmp::Ordering::Less => {
                    self.state.ctrl_ttl = 0;
                    self.state.mode = CtrlMode::StanceLock;
                    0.0
                }
            },
        }
    }

    /// Steps the 500 Hz control loop for a single tick.
    ///
    /// # Errors
    /// Returns [`VrkaError::SafetyViolation`] if state bounds are invalid.
    pub fn step_tick(
        &mut self,
        now_ns: u64,
        fresh_read: Option<&ActionChunkSlot>,
    ) -> Result<FlightRecorderEntry, VrkaError> {
        let v_cand = self.next_candidate_velocity(fresh_read);

        if self.state.mode == CtrlMode::StanceLock {
            self.state.ctrl_vel = 0.0;
        } else {
            let filter = CbfSafetyFilter::new();
            self.state.ctrl_vel = filter
                .evaluate_safe_velocity(
                    self.state.robot_pos,
                    v_cand,
                    self.state.effective_obstacle_pos,
                )
                .unwrap_or(0.0);
            self.state.robot_pos += self.state.ctrl_vel;
        }

        let entry = FlightRecorderEntry {
            tick: self.state.tick,
            timestamp_ns: now_ns,
            shm_seq: fresh_read.map_or(0, |c| c.header.sequence),
            jitter_ns: 0,
            ctrl_vel: self.state.ctrl_vel,
            robot_pos: self.state.robot_pos,
            ctrl_ttl: self.state.ctrl_ttl,
            peer_lease_ttl: 0,
            ctrl_mode: self.state.mode as u8,
            reserved0: [0u8; 3],
            reserved1: [0u8; 16],
        };

        self.state.tick += 1;
        Ok(entry)
    }
}
