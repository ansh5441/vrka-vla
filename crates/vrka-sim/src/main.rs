//! Binary stub for `vrka-sim` (deterministic `libmujoco` chaos simulator).

use std::process::ExitCode;

fn main() -> ExitCode {
    if core::hint::black_box(vrka_sim::DEFAULT_SIM_HZ) == 0 {
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}
