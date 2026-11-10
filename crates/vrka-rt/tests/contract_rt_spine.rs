//! Contract test for Phase 3 500 Hz real-time spine horizon TTL decay ladder (Scenario S-04).

use vrka_rt::{CtrlMode, RtSpine};

#[test]
#[ignore = "vrka-contract"]
fn test_s04_spine_horizon_ttl_decay() {
    let mut spine = RtSpine::new();
    let now_ns = 1_000_000_000;

    let res = spine.step_tick(now_ns, None);
    assert!(res.is_ok(), "step_tick should succeed on tick boundary");

    let entry = res.unwrap_or_else(|_| vrka_abi::FlightRecorderEntry::new_zeroed());
    assert_eq!(entry.ctrl_mode, CtrlMode::StanceLock as u8);
    assert!(entry.ctrl_vel.abs() < f32::EPSILON);
}
