#!/usr/bin/env bash
#
# mayhem/test.sh — run the Simd behavioral test oracle (built by build.sh).
#
# The oracle (simd_test_oracle) encodes a 4x4 BGR24 image to BMP, decodes it
# back, and asserts specific pixel values.  This test.sh captures the oracle's
# stdout and verifies it contains the expected PASS line — so a no-op or
# exit(0) PATCH (which produces no output) FAILS here even though exit(0) would
# succeed on the exit-code check alone.  That satisfies the anti-reward-hacking
# requirement (§6.3).
#
# Does NOT compile anything; build.sh already produced /mayhem/simd_test_oracle.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
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

ORACLE=/mayhem/simd_test_oracle
if [ ! -x "$ORACLE" ]; then
    echo "ERROR: $ORACLE not found — build.sh should have produced it" >&2
    emit_ctrf "simd-oracle" 0 1
    exit 1
fi

# Capture output AND exit code.  We verify both to be sabotage-proof:
# a no-op binary exits 0 but produces no output, so the grep below fails.
out="$("$ORACLE" 2>&1)"; rc=$?
echo "$out"

passed=0
failed=0

if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q "PASS: BMP round-trip pixel values verified"; then
    passed=$(( passed + 1 ))
else
    echo "FAIL: oracle did not emit the expected PASS line (exit=$rc)" >&2
    failed=$(( failed + 1 ))
fi

emit_ctrf "simd-oracle" "$passed" "$failed"
