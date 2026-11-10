#!/usr/bin/env bash
# Headless TLA+ and PlusCal verification runner for `vrka-vla`.
# Automatically translates PlusCal (`pcal.trans`) when present and runs `tlc2.TLC`
# on every `.tla` specification under `specs/` (or a filtered `<spec_name>`),
# failing immediately if any parse error, deadlock, or safety/liveness invariant
# violation occurs.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPECS_DIR="${TLA_SPECS_DIR:-${REPO_ROOT}/specs}"
TLA_JAR="${TLA2TOOLS_JAR:-${REPO_ROOT}/specs/tools/tla2tools.jar}"
SPEC_FILTER="${1:-}"

if [[ ! -d "${SPECS_DIR}" ]]; then
    echo "[tla-verify] ERROR: specs/ directory not found at ${SPECS_DIR}" >&2
    exit 1
fi

ALL_TLA_FILES=()
while IFS= read -r -d '' file; do
    ALL_TLA_FILES+=("${file}")
done < <(find "${SPECS_DIR}" -type f -name "*.tla" -print0 | sort -z)

TLA_FILES=()
if [[ -n "${SPEC_FILTER}" ]]; then
    for file in "${ALL_TLA_FILES[@]+"${ALL_TLA_FILES[@]}"}"; do
        [[ -z "${file}" ]] && continue
        base_no_ext="$(basename "${file}" .tla)"
        parent_dir="$(basename "$(dirname "${file}")")"
        if [[ "${base_no_ext}" == "${SPEC_FILTER}" ]] \
            || [[ "${parent_dir}" == "${SPEC_FILTER}" ]] \
            || [[ "${file}" == "${SPEC_FILTER}" ]] \
            || [[ "${file}" == "${REPO_ROOT}/${SPEC_FILTER}" ]] \
            || [[ "${file}" == "${SPECS_DIR}/${SPEC_FILTER}" ]] \
            || [[ "${file}" == "${SPECS_DIR}/${SPEC_FILTER}.tla" ]]; then
            TLA_FILES+=("${file}")
        fi
    done

    if [[ "${#TLA_FILES[@]}" -eq 0 ]]; then
        echo "[tla-verify] ERROR: Unknown or missing TLA+ specification '${SPEC_FILTER}' under ${SPECS_DIR}" >&2
        exit 1
    fi
else
    TLA_FILES=("${ALL_TLA_FILES[@]+"${ALL_TLA_FILES[@]}"}")
    if [[ "${#TLA_FILES[@]}" -eq 0 ]]; then
        echo "[tla-verify] No .tla specification files present in specs/ yet (scaffold state). Skipping TLC run."
        exit 0
    fi
fi

JAVA_BIN=""
for candidate in "${JAVA_HOME:-}/bin/java" "java" "/opt/homebrew/opt/openjdk/bin/java"; do
    if [[ -n "${candidate}" ]] && "${candidate}" -version >/dev/null 2>&1; then
        JAVA_BIN="${candidate}"
        break
    fi
done

if [[ -z "${JAVA_BIN}" ]]; then
    echo "[tla-verify] ERROR: Working 'java' runtime is required to check ${#TLA_FILES[@]} TLA+ specification(s), but none was found." >&2
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
        pcal_output=""
        pcal_rc=0
        pcal_output="$(
            cd "${spec_dir}"
            "${JAVA_BIN}" -cp "${TLA_JAR}" pcal.trans "${spec_base}.tla" 2>&1
        )" || pcal_rc=$?
        echo "${pcal_output}"
        if [[ "${pcal_rc}" -ne 0 ]] || echo "${pcal_output}" | grep -Eq 'Unrecoverable error|Error:'; then
            echo "[tla-verify] ERROR: PlusCal translation failed for ${spec_base}.tla" >&2
            exit 1
        fi
    fi

    # Run TLC model checker in headless tool mode (-deadlock checked unless overridden in .cfg)
    tlc_args=("-cleanup" "-workers" "auto" "-metadir" "${spec_dir}/.tlc_meta_${spec_base}")
    if [[ -f "${cfg_file}" ]]; then
        tlc_args+=("-config" "${spec_base}.cfg")
    fi
    tlc_args+=("${spec_base}.tla")

    tlc_output=""
    tlc_rc=0
    tlc_output="$(
        cd "${spec_dir}"
        "${JAVA_BIN}" -XX:+UseParallelGC -cp "${TLA_JAR}" tlc2.TLC "${tlc_args[@]}" 2>&1
    )" || tlc_rc=$?
    rm -rf "${spec_dir}/.tlc_meta_${spec_base}"
    echo "${tlc_output}"

    if [[ "${tlc_rc}" -ne 0 ]] \
        || echo "${tlc_output}" | grep -Eq 'Error: Invariant|Error: Deadlock reached|Error:|Parsing or semantic analysis failed|Exception' \
        || ! echo "${tlc_output}" | grep -Fq 'Model checking completed. No error has been found.'; then
        echo "[tla-verify] ERROR: TLC verification failed for ${spec_base}.tla" >&2
        exit 1
    fi
done

echo "[tla-verify] PASS: All ${#TLA_FILES[@]} TLA+ specification(s) satisfied safety and liveness invariants."
