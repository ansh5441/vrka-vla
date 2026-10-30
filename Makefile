# Canonical operational Makefile for `vrka-vla` (The Vedic Wolf Pack).
# Standardizes local development, Git hook initialization, and CI gates.

SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

.PHONY: all setup init-hooks fmt lint check-no-std check-python typecheck test verify-specs tla-check deny validate clean

all: validate

## Configure Git hooks path and verify workspace dependencies
setup: init-hooks
	cargo fetch

## Point Git at the tracked `.githooks` directory and ensure hook scripts and repo author identity are configured
init-hooks:
	chmod +x .githooks/pre-commit .githooks/pre-push scripts/check_no_std.sh scripts/verify_specs.sh
	git config core.hooksPath .githooks
	git config user.name "Anshuman"
	git config user.email "ansh5441@gmail.com"
	@echo "[init-hooks] Configured git core.hooksPath -> .githooks (author: Anshuman <ansh5441@gmail.com>)"

## Format check across Rust workspace
fmt:
	cargo fmt --all -- --check

## Run strict Clippy lints and #![no_std] default-feature verification
lint: fmt
	cargo clippy --workspace --all-targets -- -D warnings
	./scripts/check_no_std.sh

## Explicitly verify that vrka-abi, vrka-shm, and vrka-cbf remain #![no_std] under default features
check-no-std:
	./scripts/check_no_std.sh

## Run Ruff and mypy --strict on the Python proposer workspace when uv/ruff/mypy are installed
check-python:
	@if command -v uv >/dev/null 2>&1; then \
		(cd proposer && uv run ruff check . && uv run ruff format --check . && uv run mypy --strict src tests); \
	elif command -v ruff >/dev/null 2>&1 && command -v mypy >/dev/null 2>&1; then \
		(cd proposer && ruff check . && ruff format --check . && mypy --strict src tests); \
	else \
		echo "[check-python] INFO: 'uv' / 'ruff' / 'mypy' not on PATH; skipping Python check until uv is installed."; \
	fi

## Typecheck the entire workspace
typecheck:
	cargo check --workspace --all-targets
	./scripts/check_no_std.sh

## Execute all workspace unit and integration tests (including zero-allocation tests)
test:
	cargo test --workspace

## Translate PlusCal and execute headless TLC model checking on all specs/*.tla
verify-specs:
	./scripts/verify_specs.sh

## Translate PlusCal and execute headless TLC model checking on vrka_horizon_lease
tla-check:
	./scripts/verify_specs.sh vrka_horizon_lease

## Run cargo-deny supply-chain and license checks
deny:
	cargo deny check

## Full validation gate (lint + typecheck + test + verify-specs)
validate: lint typecheck test verify-specs

clean:
	cargo clean
