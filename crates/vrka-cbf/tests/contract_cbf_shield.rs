//! Contract test for Phase 3 CBF braking-distance safety shield (Scenario S-03).

use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use vrka_cbf::{braking_distance, CbfSafetyFilter};

struct CountingAllocator {
    armed: AtomicBool,
    alloc_count: AtomicUsize,
    alloc_bytes: AtomicUsize,
}

impl CountingAllocator {
    const fn new() -> Self {
        Self {
            armed: AtomicBool::new(false),
            alloc_count: AtomicUsize::new(0),
            alloc_bytes: AtomicUsize::new(0),
        }
    }

    fn reset_and_arm(&self) {
        self.alloc_count.store(0, Ordering::SeqCst);
        self.alloc_bytes.store(0, Ordering::SeqCst);
        self.armed.store(true, Ordering::SeqCst);
    }

    fn disarm_and_report(&self) -> (usize, usize) {
        self.armed.store(false, Ordering::SeqCst);
        (
            self.alloc_count.load(Ordering::SeqCst),
            self.alloc_bytes.load(Ordering::SeqCst),
        )
    }
}

// SAFETY: Delegates to standard system allocator while tracking allocations when armed.
unsafe impl GlobalAlloc for CountingAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        if self.armed.load(Ordering::SeqCst) {
            self.alloc_count.fetch_add(1, Ordering::SeqCst);
            self.alloc_bytes.fetch_add(layout.size(), Ordering::SeqCst);
        }
        // SAFETY: Direct delegation to platform System allocator.
        unsafe { System.alloc(layout) }
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        // SAFETY: Direct delegation to platform System allocator.
        unsafe { System.dealloc(ptr, layout) };
    }
}

#[global_allocator]
static ALLOCATOR: CountingAllocator = CountingAllocator::new();

#[test]
fn test_s03_cbf_braking_distance_shield() {
    assert_eq!(braking_distance(0), 0);
    assert_eq!(braking_distance(1), 1);
    assert_eq!(braking_distance(2), 3);
    assert_eq!(braking_distance(3), 6);

    let filter = CbfSafetyFilter::new();
    let robot_pos = 5.0;
    let effective_obstacle_pos = 7.0;
    let v_cand = 2.0;

    ALLOCATOR.reset_and_arm();
    let safe_vel_res = filter.evaluate_safe_velocity(robot_pos, v_cand, effective_obstacle_pos);
    let (allocs, bytes) = ALLOCATOR.disarm_and_report();

    assert!(
        safe_vel_res.is_ok(),
        "Expected safe velocity evaluation to succeed"
    );
    assert_eq!(
        allocs, 0,
        "Zero-allocation violation on CBF hot path evaluation"
    );
    assert_eq!(bytes, 0, "Allocated bytes must equal zero");

    let safe_vel = safe_vel_res.unwrap_or(0.0);
    assert!(
        safe_vel <= 1.0,
        "Candidate velocity 2.0 must be clamped to <= 1.0 at pos 5.0 with obst 7.0"
    );
    assert!(safe_vel >= 0.0);
}
