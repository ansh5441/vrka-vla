//! `#![no_std]` Control Barrier Function (CBF) safety shield crate.
//!
//! Discrete braking-distance barrier filter and continuous QP projection filter.

#![no_std]

pub use vrka_abi::{VrkaError, CACHE_LINE_BYTES};

/// Status code returned by the CBF safety filter evaluation.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ShieldStatus {
    /// Candidate velocity satisfies forward invariance without modification.
    Nominal,
    /// Candidate velocity was clamped to the maximal forward-invariant safe velocity.
    Clamped,
    /// Solver infeasibility, NaN/Inf, or boundary failure triggered stance-lock fallback.
    StanceLockFallback,
    /// Stub status indicating uninitialized solver state.
    UninitializedStub,
}

/// Evaluates discrete stopping distance at velocity `v` under unit deceleration per tick.
///
/// Verified in Phase 1 TLA+ specification ([`vrka_horizon_lease.tla`]):
/// `BrakingDistance(v) == (v * (v + 1)) \div 2`.
#[must_use]
pub const fn braking_distance(v: u32) -> u32 {
    (v * (v + 1)) / 2
}

/// `#![no_std]` Control Barrier Function safety filter.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CbfSafetyFilter;

impl CbfSafetyFilter {
    /// Creates a new CBF safety filter instance.
    #[must_use]
    pub const fn new() -> Self {
        Self
    }

    /// Evaluates forward invariance and projects candidate velocity onto the safe velocity set.
    ///
    /// # Errors
    /// Returns [`VrkaError::InvalidVelocity`] if inputs are non-finite, or [`VrkaError::NotImplemented`].
    pub fn evaluate_safe_velocity(
        &self,
        robot_pos: f32,
        v_cand: f32,
        effective_obstacle_pos: f32,
    ) -> Result<f32, VrkaError> {
        if !robot_pos.is_finite() || !v_cand.is_finite() || !effective_obstacle_pos.is_finite() {
            return Err(VrkaError::InvalidVelocity);
        }
        Err(VrkaError::NotImplemented)
    }
}
