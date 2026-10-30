# Justfile mirror of the canonical Makefile targets for `vrka-vla`

set shell := ["bash", "-euo", "pipefail", "-c"]

default: validate

# Initialize Git hooks (.githooks) and fetch Cargo dependencies
setup: init-hooks
    cargo fetch

# Point Git core.hooksPath to .githooks and configure repo author identity
init-hooks:
    chmod +x .githooks/pre-commit .githooks/pre-push scripts/check_no_std.sh scripts/verify_specs.sh
    git config core.hooksPath .githooks
    git config user.name "Anshuman"
    git config user.email "ansh5441@gmail.com"

# Check Rust formatting
fmt:
    cargo fmt --all -- --check

# Run strict Clippy and no_std checks
lint: fmt
    cargo clippy --workspace --all-targets -- -D warnings
    ./scripts/check_no_std.sh

# Verify #![no_std] default-feature purity
check-no-std:
    ./scripts/check_no_std.sh

# Typecheck workspace
typecheck:
    cargo check --workspace --all-targets
    ./scripts/check_no_std.sh

# Run workspace tests
test:
    cargo test --workspace

# Run headless TLA+ / PlusCal verification
verify-specs:
    ./scripts/verify_specs.sh

# Run cargo-deny audit
deny:
    cargo deny check

# Full validation suite
validate: lint typecheck test verify-specs
