//! Binary stub for `vrka-swarm` (`io_uring` peer lease broadcast daemon).

use std::process::ExitCode;

fn main() -> ExitCode {
    if core::hint::black_box(vrka_swarm::DEFAULT_SWARM_PORT) == 0 {
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}
