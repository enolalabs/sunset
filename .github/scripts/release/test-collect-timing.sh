#!/usr/bin/env bash
#
# test-collect-timing.sh — Truth-table test suite for collect-timing.sh.
#
# Usage: bash .github/scripts/release/test-collect-timing.sh
#
# TDD: written FIRST. Every case must fail until collect-timing.sh implements
# the timing model defined in the task brief.
#
# Fixture categories (truth table):
#   - absent      — release was created and published in this run (no draft).
#   - draft       — release ends in draft.
#   - published   — release was already published; only verify_public ran.
#   - skipped     — a job skipped (e.g. build_native in published mode).
#   - failed      — a job failed; telemetry still completes.
#   - paginated   — multiple pages of jobs (jobs list >100).
#   - null_ts     — a job lacks started_at or completed_at.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0
FAILED_NAMES=()

name()  { CURRENT_NAME="$1"; printf '  %s ... ' "$1"; }
ok()    { printf 'OK\n'; ((PASS++)); }
ko()    { printf 'FAIL\n'; ((FAIL++)); FAILED_NAMES+=("$CURRENT_NAME"); }

# run_timing <run_json> <jobs_json_dir>
# Captures exit in RT_EXIT, stdout in RT_OUT, stderr in RT_ERR.
run_timing() {
    local run_json="$1"; shift
    local jobs_dir="$1"; shift
    local out err
    out="$(mktemp)"; err="$(mktemp)"
    bash "$SCRIPT_DIR/collect-timing.sh" "$run_json" "$jobs_dir" >"$out" 2>"$err"
    RT_EXIT=$? || true
    RT_OUT="$(cat "$out")"
    RT_ERR="$(cat "$err")"
    rm -f "$out" "$err"
}

expect_pass() {
    if [[ "$RT_EXIT" -eq 0 ]]; then ok; else
        printf 'FAIL (exit %d, stderr: %s)\n' "$RT_EXIT" "${RT_ERR:0:300}"
        ((FAIL++)); FAILED_NAMES+=("$CURRENT_NAME")
    fi
}

expect_fail() {
    if [[ "$RT_EXIT" -ne 0 ]]; then ok; else
        printf 'FAIL (expected non-zero exit, got 0)\n'
        ((FAIL++)); FAILED_NAMES+=("$CURRENT_NAME")
    fi
}

expect_json_field() {
    local key="$1" expected="$2"
    local actual
    actual="$(printf '%s' "$RT_OUT" | grep -o "\"$key\":[^,}]*" | head -1)"
    if [[ "$actual" == *"$expected"* ]]; then ok; else
        printf 'FAIL (key %s: expected %s, got %s)\n' "$key" "$expected" "$actual"
        ((FAIL++)); FAILED_NAMES+=("$CURRENT_NAME")
    fi
}

expect_json_field_exists() {
    local key="$1"
    if printf '%s' "$RT_OUT" | grep -q "\"$key\":"; then ok; else
        printf 'FAIL (key %s missing)\n' "$key"
        ((FAIL++)); FAILED_NAMES+=("$CURRENT_NAME")
    fi
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

# Helper: write a job JSON object on a single line.
# Args: name conclusion started_at completed_at
job_line() {
    local name="$1" conclusion="$2" started_at="$3" completed_at="$4"
    cat <<JSON
    {"name":"$name","conclusion":"$conclusion","started_at":"$started_at","completed_at":"$completed_at"}
JSON
}

# Absent-mode run: release created and published during this run. Jobs ran
# sequentially. Native matrix had 5 rows; longest was 10m.
mkdir -p "$FIXTURE_DIR/absent"
cat > "$FIXTURE_DIR/absent/run.json" <<'JSON'
{
  "id": 1,
  "created_at": "2026-07-15T10:00:00Z",
  "run_started_at": "2026-07-15T10:00:05Z",
  "status": "completed",
  "conclusion": "success"
}
JSON
cat > "$FIXTURE_DIR/absent/jobs.json" <<'JSON'
{
  "jobs": [
    {"name":"preflight","conclusion":"success","started_at":"2026-07-15T10:00:05Z","completed_at":"2026-07-15T10:02:05Z"},
    {"name":"build_native (linux/amd64)","conclusion":"success","started_at":"2026-07-15T10:02:10Z","completed_at":"2026-07-15T10:07:10Z"},
    {"name":"build_native (linux/arm64)","conclusion":"success","started_at":"2026-07-15T10:02:10Z","completed_at":"2026-07-15T10:08:10Z"},
    {"name":"build_native (darwin/amd64)","conclusion":"success","started_at":"2026-07-15T10:02:10Z","completed_at":"2026-07-15T10:09:10Z"},
    {"name":"build_native (darwin/arm64)","conclusion":"success","started_at":"2026-07-15T10:02:10Z","completed_at":"2026-07-15T10:10:10Z"},
    {"name":"build_native (windows/amd64)","conclusion":"success","started_at":"2026-07-15T10:02:10Z","completed_at":"2026-07-15T10:07:30Z"},
    {"name":"stage_draft","conclusion":"success","started_at":"2026-07-15T10:10:20Z","completed_at":"2026-07-15T10:11:20Z"},
    {"name":"verify_draft","conclusion":"success","started_at":"2026-07-15T10:11:25Z","completed_at":"2026-07-15T10:14:25Z"},
    {"name":"promote","conclusion":"success","started_at":"2026-07-15T10:14:30Z","completed_at":"2026-07-15T10:15:30Z"},
    {"name":"verify_public","conclusion":"success","started_at":"2026-07-15T10:15:35Z","completed_at":"2026-07-15T10:18:35Z"}
  ]
}
JSON

# Draft-mode run: stops at verify_draft, no promote/verify_public.
mkdir -p "$FIXTURE_DIR/draft"
cat > "$FIXTURE_DIR/draft/run.json" <<'JSON'
{
  "id": 2,
  "created_at": "2026-07-15T11:00:00Z",
  "run_started_at": "2026-07-15T11:00:05Z",
  "status": "completed",
  "conclusion": "success"
}
JSON
cat > "$FIXTURE_DIR/draft/jobs.json" <<'JSON'
{
  "jobs": [
    {"name":"preflight","conclusion":"success","started_at":"2026-07-15T11:00:05Z","completed_at":"2026-07-15T11:02:05Z"},
    {"name":"build_native (linux/amd64)","conclusion":"success","started_at":"2026-07-15T11:02:10Z","completed_at":"2026-07-15T11:07:10Z"},
    {"name":"build_native (linux/arm64)","conclusion":"success","started_at":"2026-07-15T11:02:10Z","completed_at":"2026-07-15T11:08:10Z"},
    {"name":"build_native (darwin/amd64)","conclusion":"success","started_at":"2026-07-15T11:02:10Z","completed_at":"2026-07-15T11:09:10Z"},
    {"name":"build_native (darwin/arm64)","conclusion":"success","started_at":"2026-07-15T11:02:10Z","completed_at":"2026-07-15T11:10:10Z"},
    {"name":"build_native (windows/amd64)","conclusion":"success","started_at":"2026-07-15T11:02:10Z","completed_at":"2026-07-15T11:07:30Z"},
    {"name":"stage_draft","conclusion":"success","started_at":"2026-07-15T11:10:20Z","completed_at":"2026-07-15T11:11:20Z"},
    {"name":"verify_draft","conclusion":"success","started_at":"2026-07-15T11:11:25Z","completed_at":"2026-07-15T11:14:25Z"},
    {"name":"promote","conclusion":"skipped","started_at":null,"completed_at":null},
    {"name":"verify_public","conclusion":"skipped","started_at":null,"completed_at":null}
  ]
}
JSON

# Published-mode run: release already published. Only preflight + verify_public.
mkdir -p "$FIXTURE_DIR/published"
cat > "$FIXTURE_DIR/published/run.json" <<'JSON'
{
  "id": 3,
  "created_at": "2026-07-15T12:00:00Z",
  "run_started_at": "2026-07-15T12:00:05Z",
  "status": "completed",
  "conclusion": "success"
}
JSON
cat > "$FIXTURE_DIR/published/jobs.json" <<'JSON'
{
  "jobs": [
    {"name":"preflight","conclusion":"success","started_at":"2026-07-15T12:00:05Z","completed_at":"2026-07-15T12:02:05Z"},
    {"name":"build_native","conclusion":"skipped","started_at":null,"completed_at":null},
    {"name":"stage_draft","conclusion":"skipped","started_at":null,"completed_at":null},
    {"name":"verify_draft","conclusion":"skipped","started_at":null,"completed_at":null},
    {"name":"promote","conclusion":"skipped","started_at":null,"completed_at":null},
    {"name":"verify_public","conclusion":"success","started_at":"2026-07-15T12:02:10Z","completed_at":"2026-07-15T12:05:10Z"}
  ]
}
JSON

# Failed run: preflight failed, all downstream skipped.
mkdir -p "$FIXTURE_DIR/failed"
cat > "$FIXTURE_DIR/failed/run.json" <<'JSON'
{
  "id": 4,
  "created_at": "2026-07-15T13:00:00Z",
  "run_started_at": "2026-07-15T13:00:05Z",
  "status": "completed",
  "conclusion": "failure"
}
JSON
cat > "$FIXTURE_DIR/failed/jobs.json" <<'JSON'
{
  "jobs": [
    {"name":"preflight","conclusion":"failure","started_at":"2026-07-15T13:00:05Z","completed_at":"2026-07-15T13:01:00Z"},
    {"name":"build_native","conclusion":"skipped","started_at":null,"completed_at":null},
    {"name":"verify_public","conclusion":"skipped","started_at":null,"completed_at":null}
  ]
}
JSON

# Paginated: jobs split across two JSON pages in the directory.
mkdir -p "$FIXTURE_DIR/paginated"
cat > "$FIXTURE_DIR/paginated/run.json" <<'JSON'
{
  "id": 5,
  "created_at": "2026-07-15T14:00:00Z",
  "run_started_at": "2026-07-15T14:00:05Z",
  "status": "completed",
  "conclusion": "success"
}
JSON
cat > "$FIXTURE_DIR/paginated/jobs_1.json" <<'JSON'
{
  "jobs": [
    {"name":"preflight","conclusion":"success","started_at":"2026-07-15T14:00:05Z","completed_at":"2026-07-15T14:02:05Z"},
    {"name":"build_native (linux/amd64)","conclusion":"success","started_at":"2026-07-15T14:02:10Z","completed_at":"2026-07-15T14:05:10Z"}
  ]
}
JSON
cat > "$FIXTURE_DIR/paginated/jobs_2.json" <<'JSON'
{
  "jobs": [
    {"name":"verify_public","conclusion":"success","started_at":"2026-07-15T14:06:00Z","completed_at":"2026-07-15T14:09:00Z"}
  ]
}
JSON

# Null timestamps: a non-skipped job missing started_at/completed_at.
mkdir -p "$FIXTURE_DIR/null_ts"
cat > "$FIXTURE_DIR/null_ts/run.json" <<'JSON'
{
  "id": 6,
  "created_at": "2026-07-15T15:00:00Z",
  "run_started_at": "2026-07-15T15:00:05Z",
  "status": "completed",
  "conclusion": "success"
}
JSON
cat > "$FIXTURE_DIR/null_ts/jobs.json" <<'JSON'
{
  "jobs": [
    {"name":"preflight","conclusion":"success","started_at":"2026-07-15T15:00:05Z","completed_at":"2026-07-15T15:02:05Z"},
    {"name":"verify_public","conclusion":"success","started_at":null,"completed_at":null}
  ]
}
JSON

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

echo "Collect-timing test suite"

# Absent mode
name "absent: passes"
run_timing "$FIXTURE_DIR/absent/run.json" "$FIXTURE_DIR/absent"; expect_pass

name "absent: reports mode"
run_timing "$FIXTURE_DIR/absent/run.json" "$FIXTURE_DIR/absent"
expect_json_field "mode" "absent"

name "absent: matrix_max is 8m (longest row)"
run_timing "$FIXTURE_DIR/absent/run.json" "$FIXTURE_DIR/absent"
expect_json_field "matrix_max_seconds" "480"

name "absent: reports wall_clock_seconds"
run_timing "$FIXTURE_DIR/absent/run.json" "$FIXTURE_DIR/absent"
expect_json_field_exists "wall_clock_seconds"

name "absent: reports active_critical_path_seconds"
run_timing "$FIXTURE_DIR/absent/run.json" "$FIXTURE_DIR/absent"
expect_json_field_exists "active_critical_path_seconds"

name "absent: reports residual_seconds"
run_timing "$FIXTURE_DIR/absent/run.json" "$FIXTURE_DIR/absent"
expect_json_field_exists "residual_seconds"

name "absent: critical_path under 30min (no warning)"
run_timing "$FIXTURE_DIR/absent/run.json" "$FIXTURE_DIR/absent"
expect_json_field "over_threshold_warning" "false"

# Draft mode
name "draft: passes"
run_timing "$FIXTURE_DIR/draft/run.json" "$FIXTURE_DIR/draft"; expect_pass

name "draft: reports mode"
run_timing "$FIXTURE_DIR/draft/run.json" "$FIXTURE_DIR/draft"
expect_json_field "mode" "draft"

name "draft: skips excluded from total_job_minutes"
run_timing "$FIXTURE_DIR/draft/run.json" "$FIXTURE_DIR/draft"
expect_json_field_exists "total_job_minutes"

# Published mode
name "published: passes"
run_timing "$FIXTURE_DIR/published/run.json" "$FIXTURE_DIR/published"; expect_pass

name "published: reports mode"
run_timing "$FIXTURE_DIR/published/run.json" "$FIXTURE_DIR/published"
expect_json_field "mode" "published"

name "published: active path = preflight + verify_public"
# preflight = 12:00:05..12:02:05 = 120s; verify_public = 12:02:10..12:05:10 = 180s.
# Sum = 300s per the brief's "preflight + verify_public" formula.
run_timing "$FIXTURE_DIR/published/run.json" "$FIXTURE_DIR/published"
expect_json_field "active_critical_path_seconds" "300"

name "published: matrix_max is zero (no native rows ran)"
run_timing "$FIXTURE_DIR/published/run.json" "$FIXTURE_DIR/published"
expect_json_field "matrix_max_seconds" "0"

# Failed run
name "failed: telemetry still completes"
run_timing "$FIXTURE_DIR/failed/run.json" "$FIXTURE_DIR/failed"; expect_pass

name "failed: reports mode"
run_timing "$FIXTURE_DIR/failed/run.json" "$FIXTURE_DIR/failed"
expect_json_field "mode" "absent"

# Paginated
name "paginated: aggregates across two pages"
run_timing "$FIXTURE_DIR/paginated/run.json" "$FIXTURE_DIR/paginated"; expect_pass

name "paginated: includes jobs from both files"
run_timing "$FIXTURE_DIR/paginated/run.json" "$FIXTURE_DIR/paginated"
expect_json_field "job_count" "3"

# Null timestamps
name "null_ts: job with null timestamps excluded from duration sum"
run_timing "$FIXTURE_DIR/null_ts/run.json" "$FIXTURE_DIR/null_ts"; expect_pass

name "null_ts: telemetry emits missing_timestamps flag"
run_timing "$FIXTURE_DIR/null_ts/run.json" "$FIXTURE_DIR/null_ts"
expect_json_field "missing_timestamps" "true"

# Missing inputs
name "missing run.json fails"
run_timing "$FIXTURE_DIR/does_not_exist.json" "$FIXTURE_DIR/absent"; expect_fail

name "missing jobs dir fails"
run_timing "$FIXTURE_DIR/absent/run.json" "$FIXTURE_DIR/does_not_exist"; expect_fail

echo ""
echo "==========================================="
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
    echo "Failed tests:" >&2
    for t in "${FAILED_NAMES[@]+"${FAILED_NAMES[@]}"}"; do
        echo "  - $t" >&2
    done
    exit 1
fi
echo "All tests passed."
