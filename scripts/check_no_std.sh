#!/usr/bin/env bash
# Verify that strictly #![no_std] crates (vrka-abi, vrka-shm, vrka-cbf) do not
# import `std` in their default feature set (neither via direct source tokens
# nor via dependency feature resolution).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

NO_STD_CRATES=(
    "vrka-abi"
    "vrka-shm"
    "vrka-cbf"
)

echo "[no_std-check] Auditing default-feature no_std hygiene for: ${NO_STD_CRATES[*]}"

for crate in "${NO_STD_CRATES[@]}"; do
    crate_dir="crates/${crate}/src"
    if [[ ! -d "${crate_dir}" ]]; then
        echo "[no_std-check] ERROR: Missing source directory ${crate_dir}" >&2
        exit 1
    fi

    # 1. Verify `#![no_std]` or `#![cfg_attr(not(feature = "std"), no_std)]` is present in lib.rs
    if ! grep -Eq '^#!\[(no_std|cfg_attr\(not\(feature = "std"\), no_std\))\]' "${crate_dir}/lib.rs"; then
        echo "[no_std-check] ERROR: ${crate_dir}/lib.rs is missing mandatory #![no_std] attribute" >&2
        exit 1
    fi

    # 2. For strictly unconditional no_std crates (vrka-abi, vrka-cbf), forbid any unguarded `std::` or `extern crate std`
    if [[ "${crate}" == "vrka-abi" || "${crate}" == "vrka-cbf" ]]; then
        if grep -RInE '(^|[^a-zA-Z0-9_])(use[[:space:]]+std|extern[[:space:]]+crate[[:space:]]+std|std::)' "${crate_dir}"; then
            echo "[no_std-check] ERROR: Unconditional #![no_std] crate '${crate}' references 'std' in ${crate_dir}" >&2
            exit 1
        fi
    fi

    # 3. Verify default feature tree does not enable a `std` feature on the crate or its workspace dependencies
    tree_out="$(cargo tree --package "${crate}" --edges normal,build --format "{p} [{f}]")"
    if echo "${tree_out}" | grep -Eq '(^|[[:space:]])\[([^]]*,)?std(,[^]]*)?\]'; then
        echo "[no_std-check] ERROR: Default feature set for '${crate}' enables a 'std' feature:" >&2
        echo "${tree_out}" >&2
        exit 1
    fi

    # 4. Compile lib target with default features to prove `core`-only linkage
    cargo check --package "${crate}" --lib --quiet
done

echo "[no_std-check] PASS: All no_std crates verified clean under default features."
