//! Zero-heap-allocation verification harness for the 500 Hz hot path (Law 2).
//!
//! Uses a custom `#[global_allocator]` wrapper around [`std::alloc::System`] that counts
//! dynamic allocations on the active thread/execution scope and asserts zero allocations
//! occur inside hot-path primitives.

use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use vrka_abi::{CacheLineSlotPlaceholder, CACHE_LINE_BYTES};

/// Tracking allocator that delegates to [`System`] while recording allocations when armed.
pub struct CountingAllocator {
    armed: AtomicBool,
    alloc_count: AtomicUsize,
    alloc_bytes: AtomicUsize,
}

impl CountingAllocator {
    /// Creates an unarmed [`CountingAllocator`].
    #[must_use]
    pub const fn new() -> Self {
        Self {
            armed: AtomicBool::new(false),
            alloc_count: AtomicUsize::new(0),
            alloc_bytes: AtomicUsize::new(0),
        }
    }
}

impl Default for CountingAllocator {
    fn default() -> Self {
        Self::new()
    }
}

impl CountingAllocator {
    /// Resets counters and begins recording heap allocations.
    pub fn reset_and_arm(&self) {
        self.alloc_count.store(0, Ordering::SeqCst);
        self.alloc_bytes.store(0, Ordering::SeqCst);
        self.armed.store(true, Ordering::SeqCst);
    }

    /// Stops recording and returns `(allocation_count, allocated_bytes)`.
    #[must_use]
    pub fn disarm_and_report(&self) -> (usize, usize) {
        self.armed.store(false, Ordering::SeqCst);
        (
            self.alloc_count.load(Ordering::SeqCst),
            self.alloc_bytes.load(Ordering::SeqCst),
        )
    }
}

// SAFETY: Delegates directly to the OS `System` allocator while updating lock-free atomic counters.
unsafe impl GlobalAlloc for CountingAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        if self.armed.load(Ordering::SeqCst) {
            self.alloc_count.fetch_add(1, Ordering::SeqCst);
            self.alloc_bytes.fetch_add(layout.size(), Ordering::SeqCst);
        }
        // SAFETY: `layout` validity is guaranteed by the caller of `GlobalAlloc::alloc`.
        unsafe { System.alloc(layout) }
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        // SAFETY: `ptr` and `layout` originate from a matching `alloc` call on `System`.
        unsafe { System.dealloc(ptr, layout) }
    }
}

#[global_allocator]
static GLOBAL_ALLOC_TRACKER: CountingAllocator = CountingAllocator::new();

#[test]
fn hot_path_placeholder_performs_zero_heap_allocations() {
    assert_eq!(
        core::mem::align_of::<CacheLineSlotPlaceholder>(),
        CACHE_LINE_BYTES
    );
    assert_eq!(
        core::mem::size_of::<CacheLineSlotPlaceholder>(),
        CACHE_LINE_BYTES
    );

    GLOBAL_ALLOC_TRACKER.reset_and_arm();

    let slot = core::hint::black_box(CacheLineSlotPlaceholder::new_zeroed());
    let seq = core::hint::black_box(slot.sequence_slot);

    let (allocs, bytes) = GLOBAL_ALLOC_TRACKER.disarm_and_report();
    assert_eq!(seq, 0);
    assert_eq!(
        allocs, 0,
        "Law 2 violation: expected 0 heap allocations on hot path, observed {allocs} ({bytes} bytes)"
    );
}
