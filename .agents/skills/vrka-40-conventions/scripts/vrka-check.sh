#!/usr/bin/env bash
# Deterministic, token-free checks for the Vrka 40-series robotics & real-time SDLC loop.
# Compatible with bash 3.2 (macOS default) and BSD/GNU userlands. Run from the target repository root.

set -euo pipefail

# Ensure standard Rust / Python / Homebrew toolchains are on PATH in non-interactive subshells
for d in "$HOME/.cargo/bin" "$HOME/.local/bin" "/opt/homebrew/bin" "/usr/local/bin"; do
  [[ -d "$d" && ":$PATH:" != *":$d:"* ]] && PATH="$d:$PATH"
done
export PATH

TAB=$'\t'
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

usage() {
  cat <<'EOF'
Usage: vrka-check.sh <command> [args]

Commands:
  cmds "<shell cmd>" ...   Prove every verification command exists (make -n <target>, cargo subcommands,
                           local ./scripts/*.sh, uv/pytest runners, command -v).
  scan <base-ref> [--law1-approved] [--waive RULE:path[:line]]...
                           Scan lines added since <base-ref> (committed, staged, unstaged, untracked)
                           for Law 1/2/3 and real-time robotics invariant violations.
                           Any unwaived BLOCK exits 1; WARN-only exits 0.
  lock <sha> <file> ...    Contract-test lock: each file may differ from <sha> only by removed
                           Vrka skip markers (#[ignore = "vrka-contract"], @pytest.mark.skip(reason="vrka-contract")).
  skipped <file> ...       Fail if any #[ignore], pytest.mark.skip/xfail, or todo! markers remain in test files.
  covered <report> <S-id> ...
                           Prove each scenario has >=1 passing test and none failing or ignored, from
                           a `cargo test` log output, JUnit XML report, or `go test -json` output.

Exit codes: 0 pass, 1 violation, 2 usage or environment error.
EOF
}

die() { echo "vrka-check: $*" >&2; exit 2; }

require_git() {
  git rev-parse --show-toplevel >/dev/null 2>&1 || die "not inside a git repository"
}

TEST_PATH_RE='(^|/)(tests?|__tests__|benches|spec|testdata|fixtures?)/|[._-](test|spec)\.[A-Za-z0-9]+$|(^|/)test_[^/]*\.py$|_test\.go$|_contract\.rs$|(^|/)conftest\.py$'
SIZE_EXEMPT_RE='(^|/)(migrations?|generated|gen|specs)/|\.(gen|pb|generated|tla|cfg)\.[A-Za-z0-9]+$|\.(tla|cfg)$|_gen\.go$'
HOTPATH_PATH_RE='^crates/(vrka-abi|vrka-shm|vrka-cbf|vrka-rt|vrka-swarm|vrka-ebpf)/src/'
NOSTD_STRICT_PATH_RE='^crates/(vrka-abi|vrka-cbf|vrka-ebpf)/src/'

is_test_path() { printf '%s\n' "$1" | grep -Eq "$TEST_PATH_RE"; }
is_hotpath() { printf '%s\n' "$1" | grep -Eq "$HOTPATH_PATH_RE" && ! is_test_path "$1"; }
is_nostd_strict() { printf '%s\n' "$1" | grep -Eq "$NOSTD_STRICT_PATH_RE" && ! is_test_path "$1"; }

# ---------- cmds ----------

first_operand() {
  while [[ $# -gt 0 && ( "$1" == -* ) ]]; do shift; done
  printf '%s' "${1:-}"
}

check_make() {
  local word="$1" opts=() targets=() target
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -C|-f|--directory|--file|--makefile)
        [[ $# -ge 2 ]] || { echo "MISSING argument for make $1"; return 1; }
        opts+=("$1" "$2"); shift 2 ;;
      -*|*=*) shift ;;
      *) targets+=("$1"); shift ;;
    esac
  done
  if [[ ${#targets[@]} -eq 0 ]]; then
    "$word" ${opts[@]+"${opts[@]}"} -n >/dev/null 2>&1 || { echo "MISSING default make target"; return 1; }
    return 0
  fi
  for target in "${targets[@]}"; do
    "$word" ${opts[@]+"${opts[@]}"} -n "$target" >/dev/null 2>&1 || { echo "MISSING make target: $target"; return 1; }
  done
}

check_cargo() {
  local word="$1" sub
  shift
  command -v "$word" >/dev/null 2>&1 || { echo "MISSING executable: $word"; return 1; }
  sub="$(first_operand "$@")"
  [[ -n "$sub" ]] || return 0
  case "$sub" in
    check|test|clippy|fmt|build|run|bench|doc|tree|metadata|clean|fetch|verify-project)
      return 0 ;;
    deny|nextest|kani|miri|llvm-cov|expand|udeps)
      "$word" "$sub" --version >/dev/null 2>&1 && return 0
      echo "MISSING cargo subcommand: cargo $sub"
      return 1 ;;
    *)
      "$word" --list 2>/dev/null | awk '{print $1}' | grep -Fxq "$sub" && return 0
      echo "MISSING cargo subcommand: cargo $sub"
      return 1 ;;
  esac
}

check_python_module() {
  local mod="$1"; shift
  "$@" -c 'import importlib.util, sys; sys.exit(0 if importlib.util.find_spec(sys.argv[1]) else 1)' "$mod" >/dev/null 2>&1 && return 0
  echo "MISSING python module: $mod (via $*)"
  return 1
}

check_py_runner() {
  local word="$1" tool
  shift
  command -v "$word" >/dev/null 2>&1 || { echo "MISSING executable: $word"; return 1; }
  [[ "${1:-}" == "run" ]] || return 0
  shift
  local runner=("$word" run)
  [[ "$word" == "uv" ]] && runner=(uv run --no-sync)
  tool="$(first_operand "$@")"
  [[ -n "$tool" ]] || { echo "MISSING tool after '$word run'"; return 1; }
  if [[ "$tool" == python* && "${2:-}" == "-m" && -n "${3:-}" ]]; then
    check_python_module "$3" "${runner[@]}" "$tool"
    return
  fi
  "${runner[@]}" sh -c 'command -v "$1"' _ "$tool" >/dev/null 2>&1 && return 0
  echo "MISSING executable in $word environment: $tool"
  return 1
}

check_segment() {
  local seg="$1" word
  # Strip redirections and surrounding subshell parentheses for command existence check
  seg="$(printf '%s' "$seg" | sed -E 's/[0-9]*>&[0-9]+//g; s/[0-9]*>>?[[:space:]]*[^[:space:]]+//g; s/^[[:space:]()]+//; s/[[:space:]()]+$//')"
  set -f
  # shellcheck disable=SC2086
  set -- $seg
  set +f
  while [[ $# -gt 0 && "$1" == *=* && "$1" != -* ]]; do shift; done
  [[ $# -gt 0 ]] || return 0
  word="$1"; shift

  case "$word" in
    make|gmake) check_make "$word" "$@" ;;
    cargo) check_cargo "$word" "$@" ;;
    uv|poetry|pipenv) check_py_runner "$word" "$@" ;;
    python|python3)
      command -v "$word" >/dev/null 2>&1 || { echo "MISSING executable: $word"; return 1; }
      if [[ "${1:-}" == "-m" ]]; then check_python_module "${2:-}" "$word"; fi
      ;;
    ./*|*/*)
      [[ -x "$word" ]] || { echo "MISSING or non-executable script: $word"; return 1; }
      ;;
    cd|test|\[|true|false|echo|exit|set|export|:) ;;
    *) command -v "$word" >/dev/null 2>&1 || { echo "MISSING executable: $word"; return 1; } ;;
  esac
}

cmd_cmds() {
  [[ $# -gt 0 ]] || die "cmds requires at least one command string"
  local failed=0 cmd seg
  for cmd in "$@"; do
    while IFS= read -r seg; do
      seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
      [[ -n "$seg" ]] || continue
      if ! check_segment "$seg"; then
        echo "  in: $cmd"
        failed=1
      fi
    done < <(printf '%s\n' "$cmd" | awk '{ gsub(/&&|[|][|]|;|[|]/, "\n"); print }')
  done
  [[ $failed -eq 0 ]] && echo "cmds: OK ($# command(s))"
  return $failed
}

# ---------- scan ----------

EXCLUDE_RE='(^|/)(docs|target|node_modules|vendor|dist|build|\.vrka-wt|\.forge-wt)/|\.md$|(^|/)(Cargo\.lock|uv\.lock|poetry\.lock|package-lock\.json)$|vrka-check\.sh$|forge-check\.sh$'

# Emits "path:line<TAB>content" for every added line since base, including untracked files.
added_lines() {
  local base="$1" f
  git diff -U0 --no-color --no-ext-diff "$base" | awk '
    /^\+\+\+ / { file = substr($0, 5); sub(/^b\//, "", file); next }
    /^@@ / { split($3, a, ","); line = substr(a[1], 2) + 0; next }
    /^\+/ { if (file != "/dev/null") printf "%s:%d\t%s\n", file, line, substr($0, 2); line++ }
  '
  git ls-files --others --exclude-standard | while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    grep -Iq . "$f" 2>/dev/null || continue
    awk -v f="$f" '{ printf "%s:%d\t%s\n", f, NR, $0 }' "$f"
  done
}

# RULE|SEVERITY|CASE|SCOPE|ERE
#   SEVERITY: BLOCK | WARN | BLOCK_PROD | LAW1
#   CASE: s = sensitive, i = insensitive
#   SCOPE: all | prod | hotpath | nostd | tla | cbf
read -r -d '' SCAN_RULES <<'RULES' || true
LAW1_ORDERING|LAW1|s|prod|(Ordering::(Acquire|Release|AcqRel|SeqCst|Relaxed)|atomic::fence|compiler_fence)
LAW1_TLA|LAW1|s|tla|(.)
LAW1_CBF|LAW1|s|cbf|(.)
NO_STD_VIOLATION|BLOCK|s|nostd|((^|[^a-zA-Z0-9_])(use[[:space:]]+std|extern[[:space:]]+crate[[:space:]]+(std|alloc)|std::|alloc::))
HOTPATH_ALLOC|BLOCK|s|hotpath|((^|[^A-Za-z0-9_])(Vec::new|vec!\[|Box::new|String::new|String::from|format!\(|Arc::new|Rc::new|BTreeMap::new|HashMap::new|\.to_vec\(|\.to_string\(|\.into_boxed_slice\())
PANIC_HOTPATH|BLOCK_PROD|s|all|(\.unwrap\(\)|\.expect\(|(^|[^A-Za-z0-9_])(panic!|todo!|unimplemented!|unreachable!)\()
SUPPRESS|BLOCK|s|all|(#\[[[:space:]]*allow\(|#!\[[[:space:]]*allow\(|#[[:space:]]*type:[[:space:]]*ignore|#[[:space:]]*noqa|#[[:space:]]*pyright:[[:space:]]*ignore|//[[:space:]]*nolint|@ts-ignore|@ts-expect-error)
FLOAT_SEQ_TIME|BLOCK_PROD|i|all|((seq|sequence_slot|epoch|ttl|chunk_ttl|lease_ttl|timestamp_ns|deadline_ns)[a-z0-9_]*[[:space:]]*:[[:space:]]*(f32|f64|float))
AMBIENT_CLOCK|WARN|s|prod|(SystemTime::now\(|Instant::now\(|datetime\.now\(|datetime\.utcnow\(|time\.time\()
HOTPATH_IO|BLOCK|s|hotpath|((^|[^A-Za-z0-9_])(println!|eprintln!|dbg!|std::fs::|std::net::|thread::sleep))
FALLBACK|WARN|s|prod|(unwrap_or_default\(|except[^:]*:[[:space:]]*pass|catch[[:space:]]*(\([^)]*\))?[[:space:]]*[{][[:space:]]*[}])
SECRET_KEY|BLOCK|s|all|(-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16})
RULES

is_non_waivable() {
  case "$1" in
    LAW1_ORDERING|LAW1_TLA|LAW1_CBF|NO_STD_VIOLATION|HOTPATH_ALLOC|ABI_MISSING_ASSERT|PANIC_HOTPATH|UNDOC_UNSAFE)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

is_waived() {
  local rule="$1" path="$2" loc="$3" w
  is_non_waivable "$rule" && return 1
  for w in ${WAIVERS[@]+"${WAIVERS[@]}"}; do
    [[ "$w" == "${rule}:${path}" || "$w" == "${rule}:${loc}" ]] && return 0
  done
  return 1
}

scope_matches() {
  case "$1" in
    all) return 0 ;;
    prod) ! is_test_path "$2" ;;
    hotpath) is_hotpath "$2" ;;
    nostd) is_nostd_strict "$2" ;;
    tla) printf '%s\n' "$2" | grep -Eq '^specs/.*\.(tla|cfg)$' ;;
    cbf) printf '%s\n' "$2" | grep -Eq '^crates/vrka-cbf/src/' && ! is_test_path "$2" ;;
  esac
}

report_hit() {
  local rule="$1" sev="$2" path="$3" loc="$4" text="$5"
  if [[ "$sev" == "LAW1" ]]; then
    if [[ "$LAW1_APPROVED" -eq 1 ]]; then
      sev="WARN"
    else
      sev="BLOCK"
    fi
  elif [[ "$sev" == "BLOCK_PROD" ]]; then
    if is_test_path "$path"; then sev="WARN"; else sev="BLOCK"; fi
  fi
  if is_waived "$rule" "$path" "$loc"; then
    WAIVED=$((WAIVED + 1)); sev="WAIVED"
  elif [[ "$sev" == "BLOCK" ]]; then
    BLOCKS=$((BLOCKS + 1))
  else
    WARNS=$((WARNS + 1))
  fi
  printf '%s %s %s: %s\n' "$sev" "$rule" "$loc" "$(printf '%s' "$text" | sed -E 's/^[[:space:]]+//' | cut -c1-160)"
}

# RT-11: flag files that cross 200 lines in this diff, or grow by >20 lines when already over.
scan_file_sizes() {
  local base="$1" list="$2" f now was
  while IFS= read -r f; do
    [[ -n "$f" && -f "$f" ]] || continue
    is_test_path "$f" && continue
    printf '%s\n' "$f" | grep -Eq "$SIZE_EXEMPT_RE" && continue
    now="$(wc -l < "$f" | tr -d ' ')"
    was="$( { git show "${base}:${f}" 2>/dev/null || true; } | wc -l | tr -d ' ')"
    if [[ "$now" -gt 200 && "$was" -le 200 ]]; then
      report_hit FILE_SIZE WARN "$f" "$f" "crossed 200 lines (${was} -> ${now})"
    elif [[ "$was" -gt 200 && $((now - was)) -gt 20 ]]; then
      report_hit FILE_SIZE WARN "$f" "$f" "grew by $((now - was)) lines while over 200 (${was} -> ${now})"
    fi
  done < "$list"
}

# Law 3 (RT-03) & RT-09: check modified Rust files for #[repr(C, align(64))] without assert_cache_line_aligned!
# and unsafe blocks/impls without preceding // SAFETY: comments.
scan_rust_structural() {
  local list="$1" f
  while IFS= read -r f; do
    [[ -n "$f" && -f "$f" && "$f" == *.rs ]] || continue
    # 1. Check #[repr(C, align(64))] structs have assert_cache_line_aligned!(StructName, ...) in the same file
    while IFS=: read -r lnum struct_name; do
      [[ -n "$struct_name" ]] || continue
      if ! grep -Eq "assert_cache_line_aligned!\([[:space:]]*${struct_name}[[:space:],]" "$f"; then
        report_hit ABI_MISSING_ASSERT BLOCK "$f" "${f}:${lnum}" "#[repr(C, align(64))] struct ${struct_name} is missing assert_cache_line_aligned!(${struct_name}, ...)"
      fi
    done < <(awk '
      /#\[repr\([^]]*align\(64\)/ { align64 = 1; next }
      align64 && /^[[:space:]]*(pub(\([^)]*\))?[[:space:]]+)?struct[[:space:]]+[A-Za-z0-9_]+/ {
        line = $0
        sub(/.*struct[[:space:]]+/, "", line)
        sub(/[^A-Za-z0-9_].*/, "", line)
        printf "%d:%s\n", NR, line
        align64 = 0
      }
      align64 && /^[[:space:]]*(pub|fn|enum|union|type|impl|mod|const|static)/ && $0 !~ /struct/ {
        align64 = 0
      }
    ' "$f")

    # 2. Check unsafe blocks / unsafe impls have a // SAFETY: comment within the preceding 5 lines
    while IFS=: read -r lnum line_content; do
      [[ -n "$lnum" ]] || continue
      report_hit UNDOC_UNSAFE BLOCK "$f" "${f}:${lnum}" "unsafe block/impl without preceding '// SAFETY:' comment: ${line_content}"
    done < <(awk '
      /\/\/[[:space:]]*SAFETY:/ { safety_line = NR }
      /^[[:space:]]*\/\/!/ || /^[[:space:]]*\/\// { next }
      /(^|[^A-Za-z0-9_])unsafe[[:space:]]*(\{|impl([^A-Za-z0-9_]|$))/ {
        if (safety_line == 0 || (NR - safety_line) > 5) {
          printf "%d:%s\n", NR, $0
        }
      }
    ' "$f")
  done < "$list"
}

cmd_scan() {
  [[ $# -ge 1 ]] || die "scan requires <base-ref> [--law1-approved] [--waive RULE:path[:line]]..."
  require_git
  local base="$1" tmp hits files rule sev flag scope pat h loc path gflags
  shift
  LAW1_APPROVED=0
  WAIVERS=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --law1-approved)
        LAW1_APPROVED=1; shift ;;
      --waive)
        [[ -n "${2:-}" && "$2" == *:* ]] || die "expected --waive RULE:path[:line], got: $*"
        WAIVERS+=("$2"); shift 2 ;;
      *)
        die "unknown scan argument: $1" ;;
    esac
  done
  git rev-parse --verify --quiet "${base}^{commit}" >/dev/null || die "unknown base ref: $base"
  BLOCKS=0; WARNS=0; WAIVED=0
  tmp="$WORK/added"; hits="$WORK/hits"; files="$WORK/files"
  added_lines "$base" | awk -F"$TAB" -v re="$EXCLUDE_RE" '{ p = $1; sub(/:[0-9]+$/, "", p); if (p !~ re) print }' > "$tmp"

  while IFS='|' read -r rule sev flag scope pat; do
    [[ -n "$rule" ]] || continue
    gflags="-E"; [[ "$flag" == "i" ]] && gflags="-iE"
    grep $gflags "${TAB}.*${pat}" "$tmp" > "$hits" || true
    # Deduplicate Law 1 TLA / CBF file-level hits to first modified line per file
    if [[ "$rule" == "LAW1_TLA" || "$rule" == "LAW1_CBF" ]]; then
      awk -F: '!seen[$1]++' "$hits" > "$hits.dedup" && mv "$hits.dedup" "$hits"
    fi
    while IFS= read -r h; do
      [[ -n "$h" ]] || continue
      loc="${h%%"$TAB"*}"; path="${loc%:*}"
      scope_matches "$scope" "$path" || continue
      report_hit "$rule" "$sev" "$path" "$loc" "${h#*"$TAB"}"
    done < "$hits"
  done <<< "$SCAN_RULES"

  cut -f1 "$tmp" | sed -E 's/:[0-9]+$//' | sort -u > "$files"
  scan_rust_structural "$files"
  scan_file_sizes "$base" "$files"

  echo "scan: ${BLOCKS} BLOCK, ${WARNS} WARN, ${WAIVED} WAIVED (base ${base}, law1_approved=${LAW1_APPROVED})"
  [[ $BLOCKS -eq 0 ]]
}

# ---------- lock / skipped ----------

# Strips only the exact skip markers vrka-42 writes, so swapping a marker fails the lock.
normalize_skips() {
  sed -E \
    -e '/^[[:space:]]*#\[ignore[[:space:]]*=[[:space:]]*"vrka-contract"\][[:space:]]*$/d' \
    -e '/^[[:space:]]*@pytest\.mark\.skip\(reason="vrka-contract"\)[[:space:]]*$/d' \
    -e 's/(^|[^A-Za-z0-9_.])(it|test|describe)\.skip\(/\1\2(/g' \
    -e '/^[[:space:]]*t\.Skip\("vrka-contract"\)[[:space:]]*$/d' \
    -e '/^[[:space:]]*@Disabled\("vrka-contract"\)[[:space:]]*$/d'
}

cmd_lock() {
  [[ $# -ge 2 ]] || die "lock requires <sha> <file> ..."
  require_git
  local sha="$1" f failed=0 out
  shift
  git rev-parse --verify --quiet "${sha}^{commit}" >/dev/null || die "unknown sha: $sha"
  for f in "$@"; do
    if ! git cat-file -e "${sha}:${f}" 2>/dev/null; then
      echo "LOCK $f: not present at $sha"; failed=1; continue
    fi
    if [[ ! -f "$f" ]]; then
      echo "LOCK $f: deleted"; failed=1; continue
    fi
    if ! out="$(diff -u <(git show "${sha}:${f}" | normalize_skips) <(normalize_skips < "$f"))"; then
      echo "LOCK $f: changed beyond skip-marker removal"
      printf '%s\n' "$out" | sed -n '3,40p'
      failed=1
    fi
  done
  [[ $failed -eq 0 ]] && echo "lock: OK ($# file(s))"
  return $failed
}

cmd_skipped() {
  [[ $# -ge 1 ]] || die "skipped requires <file> ..."
  local f hits
  for f in "$@"; do [[ -f "$f" ]] || die "no such file: $f"; done
  local pat='#\[ignore([[:space:]]*=|[[:space:]]*\])|@pytest\.mark\.skip|@pytest\.mark\.xfail|@unittest\.skip|pytest\.skip\(|(^|[^A-Za-z0-9_])((it|test|describe)\.(skip|only|todo)\(|todo!\(|unimplemented!\()|t\.Skip(Now|f)?\(|@Disabled|@Ignore'
  hits="$(grep -nE "$pat" "$@" /dev/null || true)"
  if [[ -n "$hits" ]]; then
    printf '%s\n' "$hits" | sed 's/^/SKIPPED /'
    return 1
  fi
  echo "skipped: OK ($# file(s))"
}

# ---------- covered ----------

# Emits "status<TAB>test name" (status: pass | fail | skip) from a JUnit XML report.
junit_results() {
  awk '
    { buf = buf " " $0 }
    END {
      n = split(buf, parts, "<testcase")
      for (i = 2; i <= n; i++) {
        c = parts[i]; gt = index(c, ">")
        if (gt == 0) continue
        tag = substr(c, 1, gt)
        if (substr(tag, gt - 1, 1) == "/") body = ""
        else { e = index(c, "</testcase>"); body = (e > 0) ? substr(c, gt + 1, e - gt - 1) : "" }
        name = ""
        if (match(tag, /[[:space:]]name="[^"]*"/)) name = substr(tag, RSTART + 7, RLENGTH - 8)
        else if (match(tag, /[[:space:]]name=\x27[^\x27]*\x27/)) name = substr(tag, RSTART + 7, RLENGTH - 8)
        gsub(/&#x5[Bb];|&#91;|&lbrack;/, "[", name)
        gsub(/&#x5[Dd];|&#93;|&rbrack;/, "]", name)
        st = "pass"
        if (body ~ /<(failure|error)[[:space:]>\/]/) st = "fail"
        else if (body ~ /<skipped[[:space:]>\/]/ || tag ~ /[[:space:]]status="skipped"/) st = "skip"
        printf "%s\t%s\n", st, name
      }
    }' "$1"
}

# Emits "status<TAB>test name" from standard `cargo test` console output (and pytest / go test -json).
cargotest_results() {
  awk '
    /^test [A-Za-z0-9_:[\]-]+ \.\.\. (ok|FAILED|ignored)/ {
      name = $2
      res = $4
      st = "pass"
      if (res == "FAILED") st = "fail"
      else if (res == "ignored") st = "skip"
      printf "%s\t%s\n", st, name
      next
    }
    {
      a = ""; t = ""
      if (match($0, /"Action":"[a-z]+"/)) a = substr($0, RSTART + 10, RLENGTH - 11)
      if (match($0, /"Test":"[^"]*"/)) t = substr($0, RSTART + 8, RLENGTH - 9)
      if (t != "" && (a == "pass" || a == "fail" || a == "skip")) printf "%s\t%s\n", a, t
    }' "$1"
}

cmd_covered() {
  [[ $# -ge 2 ]] || die "covered requires <report> <S-id> ..."
  local report="$1" results id num re pass bad failed=0
  shift
  [[ -s "$report" ]] || die "missing or empty report: $report"
  results="$WORK/results"
  if [[ "$(head -c 4096 "$report" | tr -d ' \t\r\n' | cut -c1)" == "<" ]]; then
    junit_results "$report" > "$results"
  else
    cargotest_results "$report" > "$results"
  fi
  [[ -s "$results" ]] || die "no test results found in $report"
  for id in "$@"; do
    [[ "$id" =~ ^S-[0-9]+$ ]] || die "bad scenario id: $id"
    num="${id#S-}"
    # Tag forms: "[S-01]", "test_S01_...", "test_s01_...", "s01_...", "TestS01..."
    re="\\[${id}\\]|(^|[^A-Za-z0-9])([Tt]est_?)?[Ss]${num}([^0-9]|$)"
    pass="$(awk -F"$TAB" '$1 == "pass" { print " " $2 }' "$results" | grep -cE "$re" || true)"
    bad="$(awk -F"$TAB" '$1 != "pass" { print " " $2 }' "$results" | grep -cE "$re" || true)"
    if [[ "$pass" -eq 0 ]]; then
      echo "UNCOVERED $id: no passing test tagged [$id] / test_S${num}_*"; failed=1
    elif [[ "$bad" -gt 0 ]]; then
      echo "UNCOVERED $id: ${bad} tagged test(s) failed or ignored"; failed=1
    fi
  done
  [[ $failed -eq 0 ]] && echo "covered: OK ($# scenario(s))"
  return $failed
}

main() {
  [[ $# -ge 1 ]] || { usage >&2; exit 2; }
  local cmd="$1"; shift
  case "$cmd" in
    cmds) cmd_cmds "$@" ;;
    scan) cmd_scan "$@" ;;
    lock) cmd_lock "$@" ;;
    skipped) cmd_skipped "$@" ;;
    covered) cmd_covered "$@" ;;
    -h|--help|help) usage ;;
    *) usage >&2; exit 2 ;;
  esac
}

main "$@"
