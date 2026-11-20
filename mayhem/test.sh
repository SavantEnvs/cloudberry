#!/usr/bin/env bash
#
# mayhem/test.sh — runs upstream's libpq URI/conninfo test table (src/interfaces/libpq/t/001_uri.pl)
# against libpq_uri_regress, built by mayhem/build.sh with normal flags. exit 0 = pass. PATCH-grade oracle: after an agent patches the source, the grader
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

PROG="$SRC/mayhem/build-test/src/interfaces/libpq/test/libpq_uri_regress"
LIBDIR="$SRC/mayhem/build-test/src/interfaces/libpq"
[ -x "$PROG" ] || { echo "missing $PROG (run mayhem/build.sh)" >&2; emit_ctrf "libpq-uri-regress" 0 1 0; exit 1; }
out=$(LD_LIBRARY_PATH="$LIBDIR" perl "$SRC/mayhem/uri_regress.pl" "$SRC/src/interfaces/libpq/t/001_uri.pl" "$PROG")
rc=$?
echo "$out"
pass=$(echo "$out" | sed -n 's/^PASS \([0-9]*\) FAIL \([0-9]*\)$/\1/p')
fail=$(echo "$out" | sed -n 's/^PASS \([0-9]*\) FAIL \([0-9]*\)$/\2/p')
if [ "$rc" -ne 0 ] || [ -z "$pass" ]; then pass=${pass:-0}; fail=$(( ${fail:-0} + 1 )); fi
emit_ctrf "libpq-uri-regress" "$pass" "$fail" 0
