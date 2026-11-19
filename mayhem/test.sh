#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

OUT="$SRC/mayhem/out"
passed=0; failed=0
for t in smoke smoke_pr repl_plain; do
  [ -x "$OUT/$t" ] || { echo "missing $OUT/$t — mayhem/build.sh did not build it" >&2; exit 1; }
done

# Upstream's minctest suites print "ALL TESTS PASSED (P/T)" or "SOME TESTS FAILED (P/T)".
for t in smoke smoke_pr; do
  log=$("$OUT/$t" 2>&1); rc=$?
  echo "$log" | tail -n 3
  line=$(echo "$log" | grep -E '^(ALL TESTS PASSED|SOME TESTS FAILED) \([0-9]+/[0-9]+\)$' | tail -n1)
  if [ -n "$line" ]; then
    p=$(echo "$line" | sed -E 's/.*\(([0-9]+)\/([0-9]+)\)/\1/'); n=$(echo "$line" | sed -E 's/.*\(([0-9]+)\/([0-9]+)\)/\2/')
    passed=$((passed + p)); failed=$((failed + n - p))
    [ "$rc" -eq 0 ] || failed=$((failed + 1))
  else
    echo "FAIL $t: no minctest summary line (rc=$rc)"; failed=$((failed + 1))
  fi
done

# Known-answer checks on the repl CLI (te_interp): exact stdout for fixed input.
check_repl() {
  local input="$1" want="$2" got
  got=$(printf '%b' "$input" | "$OUT/repl_plain" 2>/dev/null)
  if [ "$got" = "$want" ]; then passed=$((passed + 1)); else
    echo "FAIL repl: input '$input' want '$want' got '$got'"; failed=$((failed + 1)); fi
}
check_repl '1+2*3\n' '7'
check_repl 'sqrt(16)^2\n2^10\n' $'16\n1024'
check_repl '(1+2\n' 'Error at position 4'
check_repl 'fac(5)+ncr(6,2)\n' '135'

emit_ctrf "minctest" "$passed" "$failed" 0
