//! Contract test for Phase 2 Seqlock IPC and cache-line ABI alignment (Scenarios S-01, S-02).

use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use vrka_abi::{
    ActionChunkSlot, FlightRecorderEntry, ShmSlotHeader, SpatialSecurityToken, CACHE_LINE_BYTES,
};
use vrka_shm::{SeqlockReader, SeqlockWriter, ShmRegionDescriptor};

/// Tracking allocator asserting zero allocations on the 500 Hz hot path (Law 2).
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

// SAFETY: Delegates directly to the standard system allocator while counting when armed.
unsafe impl GlobalAlloc for CountingAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        if self.armed.load(Ordering::SeqCst) {
            self.alloc_count.fetch_add(1, Ordering::SeqCst);
            self.alloc_bytes.fetch_add(layout.size(), Ordering::SeqCst);
        }
        // SAFETY: Delegating directly to the platform System allocator with caller layout.
        unsafe { System.alloc(layout) }
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        // SAFETY: Delegating directly to the platform System allocator with caller ptr/layout.
        unsafe { System.dealloc(ptr, layout) };
    }
}

#[global_allocator]
static ALLOCATOR: CountingAllocator = CountingAllocator::new();

#[test]
#[ignore = "vrka-contract"]
fn test_s01_shm_slot_alignment_and_zero_alloc() {
    assert_eq!(core::mem::align_of::<ShmSlotHeader>(), CACHE_LINE_BYTES);
    assert_eq!(core::mem::size_of::<ShmSlotHeader>(), 64);
    assert_eq!(core::mem::align_of::<ActionChunkSlot>(), CACHE_LINE_BYTES);
    assert_eq!(core::mem::size_of::<ActionChunkSlot>(), 128);
    assert_eq!(core::mem::size_of::<SpatialSecurityToken>(), 64);
    assert_eq!(core::mem::size_of::<FlightRecorderEntry>(), 64);

    let mut slot = ActionChunkSlot::new_zeroed();
    let mut writer = SeqlockWriter::new(&mut slot);

    let mut chunk = ActionChunkSlot::new_zeroed();
    chunk.chunk_ttl = 3;
    chunk.cmd_vel = 1.5;

    ALLOCATOR.reset_and_arm();
    let write_res = writer.write_chunk(&chunk);
    let (allocs, bytes) = ALLOCATOR.disarm_and_report();

    assert!(write_res.is_ok(), "Expected valid chunk write to succeed");
    assert_eq!(allocs, 0, "Zero-allocation violation on hot path write");
    assert_eq!(bytes, 0, "Allocated bytes must equal zero");

    let reader = SeqlockReader::new(&slot);
    let mut read_out = ActionChunkSlot::new_zeroed();

    ALLOCATOR.reset_and_arm();
    let read_res = reader.read_chunk(&mut read_out);
    let (r_allocs, r_bytes) = ALLOCATOR.disarm_and_report();

    assert!(read_res.is_ok(), "Expected valid chunk read to succeed");
    assert_eq!(r_allocs, 0, "Zero-allocation violation on hot path read");
    assert_eq!(r_bytes, 0, "Allocated bytes must equal zero");
    assert_eq!(read_out.chunk_ttl, 3);
    assert!((read_out.cmd_vel - 1.5).abs() < f32::EPSILON);
}

#[test]
#[ignore = "vrka-contract"]
fn test_s02_seqlock_boundary_rejection() {
    let unaligned = ShmRegionDescriptor { capacity_bytes: 63 };
    assert!(!unaligned.is_aligned(), "Unaligned buffer must be rejected");

    let aligned = ShmRegionDescriptor {
        capacity_bytes: 128,
    };
    assert!(
        aligned.is_aligned(),
        "64-byte aligned buffer must be accepted"
    );

    let mut nan_chunk = ActionChunkSlot::new_zeroed();
    nan_chunk.cmd_vel = f32::NAN;
    nan_chunk.chunk_ttl = 3;
    assert!(!nan_chunk.is_valid(), "NaN velocity must be rejected");

    let mut zero_ttl_chunk = ActionChunkSlot::new_zeroed();
    zero_ttl_chunk.cmd_vel = 1.0;
    zero_ttl_chunk.chunk_ttl = 0;
    assert!(!zero_ttl_chunk.is_valid(), "Zero TTL must be rejected");

    let mut slot = ActionChunkSlot::new_zeroed();
    let mut writer = SeqlockWriter::new(&mut slot);
    assert!(
        writer.write_chunk(&nan_chunk).is_err(),
        "Writer must reject NaN"
    );
}
