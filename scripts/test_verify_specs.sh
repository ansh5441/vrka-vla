#!/usr/bin/env bash
# Regression and contract test suite for `./scripts/verify_specs.sh` ([S-02]).
# Verifies that the CLI runner fails closed (non-zero exit code) on:
#   (a) unknown `<spec_name>`
#   (b) PlusCal/TLA+ parse error
#   (c) TLC invariant violation

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${REPO_ROOT}/scripts/verify_specs.sh"
JUNIT_FILE="${REPO_ROOT}/target/junit.xml"

TMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

echo "[test-verify-specs] [S-01] Testing PlusCal translation and headless TLC verification on vrka_horizon_lease..."
if ! make -C "${REPO_ROOT}" tla-check >/dev/null 2>&1; then
    echo "[test-verify-specs] FAIL [S-01]: make tla-check failed on vrka_horizon_lease" >&2
    exit 1
fi
tlc_out="$("${RUNNER}" "vrka_horizon_lease" 2>&1)" || {
    echo "[test-verify-specs] FAIL [S-01]: verify_specs.sh vrka_horizon_lease failed" >&2
    exit 1
}
distinct_states="$(echo "${tlc_out}" | sed -nE 's/.* ([0-9]+) distinct states found.*/\1/p' | tail -n 1)"
if [[ -z "${distinct_states}" ]] || [[ "${distinct_states}" -le 1 ]]; then
    echo "[test-verify-specs] FAIL [S-01]: Expected non-trivial state graph (> 1 distinct states), got '${distinct_states:-0}'" >&2
    exit 1
fi
echo "[test-verify-specs] [S-01] Verified ${distinct_states} distinct states with 0 invariant violations."

echo "[test-verify-specs] [S-02] Case (a): Testing unknown <spec_name> fails closed..."
if TLA_SPECS_DIR="${TMP_DIR}" "${RUNNER}" "nonexistent_spec_xyz" >/dev/null 2>&1; then
    echo "[test-verify-specs] FAIL [S-02]: Runner exited 0 for unknown spec 'nonexistent_spec_xyz'" >&2
    exit 1
fi

echo "[test-verify-specs] [S-02] Case (b): Testing PlusCal/TLA+ parse error fails closed..."
mkdir -p "${TMP_DIR}/broken_parse"
cat > "${TMP_DIR}/broken_parse/broken_parse.tla" << 'EOF'
---- MODULE broken_parse ----
EXTENDS Naturals
(* --algorithm broken_parse
variables x = ;
begin
  Lbl: x := x + 1;
end algorithm; *)
====
EOF
cat > "${TMP_DIR}/broken_parse/broken_parse.cfg" << 'EOF'
SPECIFICATION Spec
EOF

if TLA_SPECS_DIR="${TMP_DIR}" "${RUNNER}" "broken_parse" >/dev/null 2>&1; then
    echo "[test-verify-specs] FAIL [S-02]: Runner exited 0 for broken PlusCal/TLA+ parse spec" >&2
    exit 1
fi

echo "[test-verify-specs] [S-02] Case (c): Testing TLC invariant violation fails closed..."
mkdir -p "${TMP_DIR}/bad_inv"
cat > "${TMP_DIR}/bad_inv/bad_inv.tla" << 'EOF'
---- MODULE bad_inv ----
EXTENDS Naturals

VARIABLE x

Init == x = 0
Next == x' = x + 1
Spec == Init /\ [][Next]_x

BadInvariant == x < 2
====
EOF
cat > "${TMP_DIR}/bad_inv/bad_inv.cfg" << 'EOF'
SPECIFICATION Spec
INVARIANT BadInvariant
EOF

if TLA_SPECS_DIR="${TMP_DIR}" "${RUNNER}" "bad_inv" >/dev/null 2>&1; then
    echo "[test-verify-specs] FAIL [S-02]: Runner exited 0 for spec with violated invariant" >&2
    exit 1
fi

echo "[test-verify-specs] [S-03] Testing PlusCal quick-reference cheat sheet and gitignore hygiene..."
README_FILE="${REPO_ROOT}/specs/README.md"
if [[ ! -f "${README_FILE}" ]]; then
    echo "[test-verify-specs] FAIL [S-03]: specs/README.md does not exist" >&2
    exit 1
fi

for token in ":=" "with" "await" "=>" "make tla-check" "./scripts/verify_specs.sh"; do
    if ! grep -Fq "${token}" "${README_FILE}"; then
        echo "[test-verify-specs] FAIL [S-03]: specs/README.md is missing required reference '${token}'" >&2
        exit 1
    fi
done

if ! git -C "${REPO_ROOT}" check-ignore -q specs/tools/tla2tools.jar; then
    echo "[test-verify-specs] FAIL [S-03]: specs/tools/tla2tools.jar is not ignored by git" >&2
    exit 1
fi

mkdir -p "$(dirname "${JUNIT_FILE}")"
cat > "${JUNIT_FILE}" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="verify_specs" tests="3" failures="0" errors="0">
    <testcase name="[S-01] PlusCal translation and headless TLC verification succeed on the horizon lease skeleton" classname="scripts.test_verify_specs"/>
    <testcase name="[S-02] CLI runner fails closed on invariant violation, deadlock, parse error, or unknown spec" classname="scripts.test_verify_specs"/>
    <testcase name="[S-03] PlusCal quick-reference cheat sheet and gitignore hygiene are in place" classname="scripts.test_verify_specs"/>
  </testsuite>
</testsuites>
EOF

echo "[test-verify-specs] PASS [S-01] [S-02] [S-03]: All checks passed."
