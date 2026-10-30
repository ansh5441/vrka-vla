#!/usr/bin/env bash
# Headless TLA+ and PlusCal verification runner for `vrka-vla`.
# Automatically translates PlusCal (`pcal.trans`) when present and runs `tlc2.TLC`
# on every `.tla` specification under `specs/`, failing immediately if any safety
# or liveness invariant is violated.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPECS_DIR="${REPO_ROOT}/specs"
TLA_JAR="${TLA2TOOLS_JAR:-${SPECS_DIR}/tools/tla2tools.jar}"

if [[ ! -d "${SPECS_DIR}" ]]; then
    echo "[tla-verify] ERROR: specs/ directory not found at ${SPECS_DIR}" >&2
    exit 1
fi

TLA_FILES=()
while IFS= read -r -d '' file; do
    TLA_FILES+=("${file}")
done < <(find "${SPECS_DIR}" -type f -name "*.tla" -print0 | sort -z)

if [[ "${#TLA_FILES[@]}" -eq 0 ]]; then
    echo "[tla-verify] No .tla specification files present in specs/ yet (scaffold state). Skipping TLC run."
    exit 0
fi

if ! command -v java >/dev/null 2>&1; then
    echo "[tla-verify] ERROR: 'java' runtime is required to check ${#TLA_FILES[@]} TLA+ specification(s), but was not found." >&2
    exit 1
fi

if [[ ! -f "${TLA_JAR}" ]]; then
    echo "[tla-verify] ERROR: tla2tools.jar not found at ${TLA_JAR}." >&2
    echo "[tla-verify] Place tla2tools.jar in specs/tools/tla2tools.jar or export TLA2TOOLS_JAR=/path/to/tla2tools.jar." >&2
    exit 1
fi

for tla_file in "${TLA_FILES[@]}"; do
    spec_dir="$(dirname "${tla_file}")"
    spec_base="$(basename "${tla_file}" .tla)"
    cfg_file="${spec_dir}/${spec_base}.cfg"

    echo "[tla-verify] Checking ${tla_file}..."

    # Translate PlusCal algorithm if the file contains a `--algorithm` or `--fair algorithm` block
    if grep -Eq '\-\-(fair[[:space:]]+)?algorithm' "${tla_file}"; then
        echo "[tla-verify] Translating PlusCal in ${spec_base}.tla..."
        (
            cd "${spec_dir}"
            java -XX:+UseParallelGC -cp "${TLA_JAR}" pcal.trans "${spec_base}.tla"
        )
    fi

    # Run TLC model checker in headless tool mode (-deadlock checked unless overridden in .cfg)
    tlc_args=("-cleanup" "-workers" "auto" "-metadir" "${spec_dir}/.tlc_meta_${spec_base}")
    if [[ -f "${cfg_file}" ]]; then
        tlc_args+=("-config" "${spec_base}.cfg")
    fi
    tlc_args+=("${spec_base}.tla")

    (
        cd "${spec_dir}"
        java -XX:+UseParallelGC -cp "${TLA_JAR}" tlc2.TLC "${tlc_args[@]}"
    )
    rm -rf "${spec_dir}/.tlc_meta_${spec_base}"
done

echo "[tla-verify] PASS: All ${#TLA_FILES[@]} TLA+ specification(s) satisfied safety and liveness invariants."
