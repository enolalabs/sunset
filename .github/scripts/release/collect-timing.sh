#!/usr/bin/env bash
#
# collect-timing.sh — Compute release-workflow timing metrics.
#
# Usage:
#   collect-timing.sh <run.json> <jobs-dir>
#
# Inputs:
#   run.json    Single workflow-run object from the GitHub REST API.
#   jobs-dir    Directory containing one or more JSON files, each holding a
#               workflow-jobs listing (the result of paginated
#               `gh api repos/:o/:r/actions/runs/:id/jobs`). Every JSON file
#               in the directory is read and its `jobs` array concatenated.
#
# Output:
#   A single JSON object on stdout summarising the timing model:
#
#   {
#     "run_id": <int>,
#     "mode": "absent" | "draft" | "published",
#     "wall_clock_seconds": <int>,
#     "total_job_minutes": <int>,
#     "matrix_max_seconds": <int>,
#     "active_critical_path_seconds": <int>,
#     "residual_seconds": <int>,
#     "job_count": <int>,
#     "missing_timestamps": <bool>,
#     "over_threshold_warning": <bool>
#   }
#
# Model (per Task 5 brief):
#   - job duration  = completed_at - started_at  (per non-skipped job)
#   - total job-minutes = sum of non-skipped measured jobs (rounded up)
#   - matrix duration = longest native matrix row (max duration of any job
#     whose name contains `(`)
#   - absent active critical path = preflight + build_native(matrix_max) +
#     stage_draft + verify_draft + promote + verify_public  (sequential)
#   - published active path = preflight + verify_public
#   - wall-clock = telemetry observation time (now) - workflow created_at
#   - residual = wall-clock - active-critical-path
#   - Missing required timing data fails ONLY this script (telemetry job).
#   - Absent-mode critical path >30min emits warning, not failure.
#
set -uo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: collect-timing.sh <run.json> <jobs-dir>" >&2
    exit 2
fi

RUN_JSON="$1"
JOBS_DIR="$2"

if [[ ! -f "$RUN_JSON" ]]; then
    echo "collect-timing: run.json not found: $RUN_JSON" >&2
    exit 1
fi
if [[ ! -d "$JOBS_DIR" ]]; then
    echo "collect-timing: jobs dir not found: $JOBS_DIR" >&2
    exit 1
fi

# We rely on Python 3 for ISO-8601 parsing and JSON walking. Python is present
# on every GitHub Actions runner image. Refuse to run without it.
if ! command -v python3 >/dev/null 2>&1; then
    echo "collect-timing: python3 is required" >&2
    exit 1
fi

# Concatenate all jobs arrays across the directory so we handle pagination.
jobs_json="$(mktemp)"
trap 'rm -f "$jobs_json"' EXIT

# Build a single combined JSON list of jobs by walking every *.json file
# (sorted for determinism) and pulling the `jobs` array from each.
python3 - "$RUN_JSON" "$JOBS_DIR" "$jobs_json" <<'PY'
import json
import os
import sys
import glob
import datetime
import math

run_path = sys.argv[1]
jobs_dir = sys.argv[2]
out_path = sys.argv[3]

with open(run_path, "r", encoding="utf-8") as fh:
    run = json.load(fh)

combined_jobs = []
for fp in sorted(glob.glob(os.path.join(jobs_dir, "*.json"))):
    with open(fp, "r", encoding="utf-8") as fh:
        try:
            data = json.load(fh)
        except json.JSONDecodeError as exc:
            print(f"collect-timing: cannot parse {fp}: {exc}", file=sys.stderr)
            sys.exit(1)
    if isinstance(data, dict) and isinstance(data.get("jobs"), list):
        combined_jobs.extend(data["jobs"])

with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(combined_jobs, fh)
PY

# Now compute the timing model in Python, reading both files.
now_epoch="$(date -u +%s)"

python3 - "$RUN_JSON" "$jobs_json" "$now_epoch" <<'PY'
import json
import os
import sys
import re
import datetime
import math

run_path = sys.argv[1]
jobs_path = sys.argv[2]
now_epoch = int(sys.argv[3])

with open(run_path, "r", encoding="utf-8") as fh:
    run = json.load(fh)
with open(jobs_path, "r", encoding="utf-8") as fh:
    jobs = json.load(fh)

def parse_iso(ts):
    """Parse a GitHub ISO-8601 timestamp to epoch seconds. None on failure."""
    if not ts:
        return None
    # GitHub uses trailing 'Z' for UTC.
    if ts.endswith("Z"):
        ts = ts[:-1] + "+00:00"
    try:
        dt = datetime.datetime.fromisoformat(ts)
        return int(dt.timestamp())
    except (ValueError, TypeError):
        return None

def duration_seconds(job):
    s = parse_iso(job.get("started_at"))
    e = parse_iso(job.get("completed_at"))
    if s is None or e is None:
        return None
    return max(0, e - s)

# Map jobs by their base name. Matrix rows appear as `name (os/arch)`.
def base_name(n):
    if not n:
        return ""
    # Strip ` (anything)` suffix.
    return re.sub(r"\s*\([^)]*\)\s*$", "", n).strip()

by_name = {}
matrix_rows = []
missing_timestamps = False
non_skipped_durations = []  # (base_name, seconds)
total_job_seconds = 0

for j in jobs:
    name = j.get("name", "")
    conclusion = j.get("conclusion", "")
    bn = base_name(name)
    dur = duration_seconds(j)
    if conclusion == "skipped":
        # Skipped jobs contribute nothing to the totals.
        continue
    if dur is None:
        # Non-skipped job lacking timestamps.
        missing_timestamps = True
        continue
    total_job_seconds += dur
    non_skipped_durations.append((bn, dur))
    if bn not in by_name:
        by_name[bn] = dur
    else:
        # If the same base name appears multiple times (e.g. matrix re-runs),
        # keep the longest.
        if dur > by_name[bn]:
            by_name[bn] = dur
    # A matrix row carries ` (os/arch)` in its name.
    if "(" in name and ")" in name:
        matrix_rows.append((name, dur))

# Matrix max = longest single matrix row.
matrix_max = max((d for _, d in matrix_rows), default=0)

# Determine mode from the run. We treat:
#   - If promote ran AND verify_public ran AND none of stage_draft/verify_draft
#     was skipped-but-present, the run published the release in-band → "absent"
#     (the release was absent at start, now public).
#   - If promote was skipped but stage_draft ran → "draft".
#   - If build_native was entirely skipped (release already published) →
#     "published".
# These heuristics let us compute timing from job data alone.
job_names_seen = {base_name(j.get("name", "")) for j in jobs}
job_conclusions = {base_name(j.get("name", "")): j.get("conclusion", "") for j in jobs}

def had(name):
    return any(base_name(j.get("name", "")) == name for j in jobs)

def concl(name):
    return job_conclusions.get(name, None)

build_native_ran = any(
    base_name(j.get("name", "")) == "build_native"
    and j.get("conclusion") != "skipped"
    for j in jobs
)
# "published" mode means preflight *succeeded*, determined the release was
# already public, and therefore skipped every write-capable job. A run where
# preflight itself failed cannot be classified as published: we have no
# reliable mode signal and default to "absent".
preflight_success = any(
    base_name(j.get("name", "")) == "preflight"
    and j.get("conclusion") == "success"
    for j in jobs
)
promote_ran = any(
    base_name(j.get("name", "")) == "promote"
    and j.get("conclusion") != "skipped"
    for j in jobs
)
promote_present = had("promote")
stage_ran = any(
    base_name(j.get("name", "")) == "stage_draft"
    and j.get("conclusion") != "skipped"
    for j in jobs
)

if preflight_success and not build_native_ran and had("build_native"):
    mode = "published"
elif promote_ran:
    mode = "absent"
elif stage_ran and not promote_ran:
    mode = "draft"
else:
    # Fallback: if no signal, default to absent (the most common case).
    # This covers preflight-failed runs where the mode is indeterminate.
    mode = "absent"

# Active critical path:
#   absent   = preflight + matrix_max + stage_draft + verify_draft + promote + verify_public
#   draft    = preflight + matrix_max + stage_draft + verify_draft
#   published = preflight + verify_public
def stage_sec(name):
    return by_name.get(name, 0)

if mode == "published":
    active = stage_sec("preflight") + stage_sec("verify_public")
elif mode == "draft":
    active = (
        stage_sec("preflight")
        + matrix_max
        + stage_sec("stage_draft")
        + stage_sec("verify_draft")
    )
else:  # absent
    active = (
        stage_sec("preflight")
        + matrix_max
        + stage_sec("stage_draft")
        + stage_sec("verify_draft")
        + stage_sec("promote")
        + stage_sec("verify_public")
    )

# Wall-clock = now - run created_at.
created = parse_iso(run.get("created_at"))
if created is None:
    print("collect-timing: run.created_at missing or unparseable", file=sys.stderr)
    sys.exit(1)

wall_clock = max(0, now_epoch - created)
residual = max(0, wall_clock - active)

# Total job-minutes: ceiling of total seconds / 60.
total_job_minutes = int(math.ceil(total_job_seconds / 60.0))

# Over-threshold warning: absent-mode critical path > 30 min.
threshold_seconds = 30 * 60
over_threshold = (mode == "absent" and active > threshold_seconds)

out = {
    "run_id": run.get("id"),
    "mode": mode,
    "wall_clock_seconds": wall_clock,
    "total_job_minutes": total_job_minutes,
    "matrix_max_seconds": matrix_max,
    "active_critical_path_seconds": active,
    "residual_seconds": residual,
    "job_count": len(jobs),
    "missing_timestamps": bool(missing_timestamps),
    "over_threshold_warning": bool(over_threshold),
}

print(json.dumps(out))
PY
