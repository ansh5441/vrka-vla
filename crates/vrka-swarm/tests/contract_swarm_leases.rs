//! Contract test for Phase 4 swarm peer lease tightening and decay (Scenario S-05).

use vrka_abi::{assert_cache_line_aligned, CACHE_LINE_BYTES};
use vrka_swarm::{PeerLeaseAggregator, PeerLeaseFrame, DEFAULT_THREAT_POS};

assert_cache_line_aligned!(PeerLeaseFrame, 128);

#[test]
fn test_s05_swarm_peer_lease_tightening() {
    assert_eq!(core::mem::align_of::<PeerLeaseFrame>(), CACHE_LINE_BYTES);
    assert_eq!(core::mem::size_of::<PeerLeaseFrame>(), 128);

    let mut aggregator = PeerLeaseAggregator::new(DEFAULT_THREAT_POS);
    assert!((aggregator.effective_obstacle_pos() - DEFAULT_THREAT_POS).abs() < f32::EPSILON);

    let mut frame = PeerLeaseFrame::new_zeroed();
    frame.peer_pos = 4.0;
    frame.peer_vel = 0.5;
    frame.peer_lease_ttl = 3;

    let res = aggregator.ingest_frame(&frame);
    assert!(res.is_ok(), "Ingesting valid peer lease frame must succeed");
    assert!((aggregator.effective_obstacle_pos() - 4.0).abs() < f32::EPSILON);

    aggregator.step_tick();
    aggregator.step_tick();
    aggregator.step_tick();
    assert!((aggregator.effective_obstacle_pos() - DEFAULT_THREAT_POS).abs() < f32::EPSILON);
}
