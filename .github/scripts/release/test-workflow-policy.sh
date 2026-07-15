#!/usr/bin/env bash
#
# test-workflow-policy.sh — Truth-table test suite for verify-workflow-policy.sh.
#
# Usage: bash .github/scripts/release/test-workflow-policy.sh
#
# TDD: this file is written FIRST. Every fixture below MUST fail until the
# policy helper exists and enforces every rule.
#
# Fixture categories (truth table):
#   Positive:
#     - valid_release         — model release.yml with all four pinned actions,
#                                checkouts isolated, finite timeouts.
#     - valid_validation      — model release-validation.yml, no write permission.
#     - valid_local_action    — `uses: ./local-action` permitted.
#   Negative:
#     - stable_tag            — `actions/checkout@v4` rejected.
#     - branch_ref            — `actions/checkout@main` rejected.
#     - short_sha             — `actions/checkout@34e1148` rejected.
#     - unknown_action        — `foo/bar@<sha>` rejected.
#     - missing_isolation     — checkout without persist-credentials: false.
#     - missing_timeout       — job without timeout-minutes.
#     - write_in_validation   — write permission in validation workflow.
#     - softprops_reference   — softprops/action-gh-release@<sha> rejected.
#     - goreleaser_reference  — mention of goreleaser rejected.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

PASS=0
FAIL=0
FAILED_NAMES=()

name()  { CURRENT_NAME="$1"; printf '  %s ... ' "$1"; }
ok()    { printf 'OK\n'; ((PASS++)); }
ko()    { printf 'FAIL\n'; ((FAIL++)); FAILED_NAMES+=("$CURRENT_NAME"); }

# run_policy <fixture_path> [args...]
# Captures exit code in RP_EXIT, stdout in RP_STDOUT, stderr in RP_STDERR.
run_policy() {
    local out err
    out="$(mktemp)"; err="$(mktemp)"
    bash "$SCRIPT_DIR/verify-workflow-policy.sh" "$@" >"$out" 2>"$err"
    RP_EXIT=$? || true
    RP_STDOUT="$(cat "$out")"
    RP_STDERR="$(cat "$err")"
    rm -f "$out" "$err"
}

expect_pass() {
    if [[ "$RP_EXIT" -eq 0 ]]; then ok; else
        printf 'FAIL (exit %d, stderr: %s)\n' "$RP_EXIT" "${RP_STDERR:0:300}"
        ((FAIL++)); FAILED_NAMES+=("$CURRENT_NAME")
    fi
}

expect_fail() {
    if [[ "$RP_EXIT" -ne 0 ]]; then ok; else
        printf 'FAIL (expected non-zero exit, got 0)\n'
        ((FAIL++)); FAILED_NAMES+=("$CURRENT_NAME")
    fi
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

# A model release.yml fixture that satisfies every rule.
cat > "$FIXTURE_DIR/valid_release.yml" <<'YAML'
name: Release
on:
  push:
    tags: ["v*"]
permissions:
  contents: read
jobs:
  preflight:
    runs-on: ubuntu-24.04
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4
        with:
          persist-credentials: false
      - uses: actions/setup-go@40f1582b2485089dde7abd97c1529aa768e1baff # v5
        with:
          go-version-file: go.mod
  upload:
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4
        with:
          name: out
          path: out
YAML

# A model release-validation.yml: no write permission.
cat > "$FIXTURE_DIR/valid_validation.yml" <<'YAML'
name: Release Validation
on:
  workflow_dispatch:
    inputs:
      commit_sha:
        required: true
permissions:
  contents: read
jobs:
  validate_preflight:
    runs-on: ubuntu-24.04
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4
        with:
          persist-credentials: false
      - uses: actions/setup-go@40f1582b2485089dde7abd97c1529aa768e1baff # v5
        with:
          go-version-file: go.mod
YAML

# A fixture with a local composite action — must be permitted.
cat > "$FIXTURE_DIR/valid_local.yml" <<'YAML'
name: Local
on:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  one:
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4
        with:
          persist-credentials: false
      - uses: ./.github/actions/local-thing
YAML

# Negative: @v4 stable tag.
cat > "$FIXTURE_DIR/stable_tag.yml" <<'YAML'
name: Bad
on: { push: { branches: [main] } }
permissions: { contents: read }
jobs:
  one:
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
YAML

# Negative: branch ref.
cat > "$FIXTURE_DIR/branch_ref.yml" <<'YAML'
name: Bad
on: { push: { branches: [main] } }
permissions: { contents: read }
jobs:
  one:
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@main
        with:
          persist-credentials: false
YAML

# Negative: short SHA.
cat > "$FIXTURE_DIR/short_sha.yml" <<'YAML'
name: Bad
on: { push: { branches: [main] } }
permissions: { contents: read }
jobs:
  one:
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@34e1148
        with:
          persist-credentials: false
YAML

# Negative: unknown action (even with valid SHA).
cat > "$FIXTURE_DIR/unknown_action.yml" <<'YAML'
name: Bad
on: { push: { branches: [main] } }
permissions: { contents: read }
jobs:
  one:
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - uses: actions/unknown@34e114876b0b11c390a56381ad16ebd13914f8d5
        with:
          persist-credentials: false
YAML

# Negative: missing persist-credentials: false in checkout.
cat > "$FIXTURE_DIR/missing_isolation.yml" <<'YAML'
name: Bad
on: { push: { branches: [main] } }
permissions: { contents: read }
jobs:
  one:
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4
      - uses: actions/setup-go@40f1582b2485089dde7abd97c1529aa768e1baff # v5
        with:
          go-version-file: go.mod
YAML

# Negative: missing timeout-minutes on a job.
cat > "$FIXTURE_DIR/missing_timeout.yml" <<'YAML'
name: Bad
on: { push: { branches: [main] } }
permissions: { contents: read }
jobs:
  one:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4
        with:
          persist-credentials: false
YAML

# Negative: write permission in validation workflow.
cat > "$FIXTURE_DIR/write_in_validation.yml" <<'YAML'
name: Bad
on:
  workflow_dispatch:
permissions:
  contents: write
jobs:
  one:
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4
        with:
          persist-credentials: false
YAML

# Negative: softprops reference.
cat > "$FIXTURE_DIR/softprops.yml" <<'YAML'
name: Bad
on: { push: { branches: [main] } }
permissions: { contents: read }
jobs:
  one:
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4
        with:
          persist-credentials: false
      - uses: softprops/action-gh-release@ea165f8d65b6e75b540449e92b4886f43607fa02
YAML

# Negative: goreleaser reference (in a run: step string).
cat > "$FIXTURE_DIR/goreleaser.yml" <<'YAML'
name: Bad
on: { push: { branches: [main] } }
permissions: { contents: read }
jobs:
  one:
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4
        with:
          persist-credentials: false
      - name: Run goreleaser
        run: goreleaser release
YAML

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

echo "Workflow policy test suite"

# Positive cases
name "valid_release passes"
run_policy "$FIXTURE_DIR/valid_release.yml"; expect_pass

name "valid_validation passes"
run_policy "$FIXTURE_DIR/valid_validation.yml"; expect_pass

name "valid_local_action passes"
run_policy "$FIXTURE_DIR/valid_local.yml"; expect_pass

# Default mode rejects write-permission workflow? No — write is allowed in
# release.yml. Only --reject-write mode rejects it.
name "write_in_validation ignored without --reject-write"
run_policy "$FIXTURE_DIR/write_in_validation.yml"; expect_pass

name "valid_release passes with --reject-write"
run_policy --reject-write "$FIXTURE_DIR/valid_release.yml"; expect_pass

name "valid_validation passes with --reject-write"
run_policy --reject-write "$FIXTURE_DIR/valid_validation.yml"; expect_pass

name "write_in_validation rejected with --reject-write"
run_policy --reject-write "$FIXTURE_DIR/write_in_validation.yml"; expect_fail

# Negative cases — action pin rules
name "stable_tag rejected"
run_policy "$FIXTURE_DIR/stable_tag.yml"; expect_fail

name "branch_ref rejected"
run_policy "$FIXTURE_DIR/branch_ref.yml"; expect_fail

name "short_sha rejected"
run_policy "$FIXTURE_DIR/short_sha.yml"; expect_fail

name "unknown_action rejected"
run_policy "$FIXTURE_DIR/unknown_action.yml"; expect_fail

# Negative cases — checkout isolation
name "missing_isolation rejected"
run_policy "$FIXTURE_DIR/missing_isolation.yml"; expect_fail

# Negative cases — timeouts
name "missing_timeout rejected"
run_policy "$FIXTURE_DIR/missing_timeout.yml"; expect_fail

# Negative cases — forbidden references
name "softprops rejected"
run_policy "$FIXTURE_DIR/softprops.yml"; expect_fail

name "goreleaser rejected"
run_policy "$FIXTURE_DIR/goreleaser.yml"; expect_fail

# Multiple files at once
name "two valid files together pass"
run_policy "$FIXTURE_DIR/valid_release.yml" "$FIXTURE_DIR/valid_validation.yml"; expect_pass

name "valid + invalid together fail"
run_policy "$FIXTURE_DIR/valid_release.yml" "$FIXTURE_DIR/stable_tag.yml"; expect_fail

# Missing file
name "nonexistent file fails"
run_policy "$FIXTURE_DIR/does_not_exist.yml"; expect_fail

# Real workflows (if they exist)
RELEASE_YAML="$REPO_ROOT/.github/workflows/release.yml"
VALIDATION_YAML="$REPO_ROOT/.github/workflows/release-validation.yml"
if [[ -f "$RELEASE_YAML" && -f "$VALIDATION_YAML" ]]; then
    name "repo release.yml passes"
    run_policy "$RELEASE_YAML"; expect_pass
    name "repo release-validation.yml passes (--reject-write)"
    run_policy --reject-write "$VALIDATION_YAML"; expect_pass
fi

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
