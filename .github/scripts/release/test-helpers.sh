#!/usr/bin/env bash
#
# test-helpers.sh — POSIX test suite for the native release helpers.
#
# Usage: bash .github/scripts/release/test-helpers.sh
#
# This file is deliberately written FIRST (TDD). It exercises every contract
# of smoke.sh, package-and-verify.sh, and verify-consumer.sh by using stub
# executables with controllable behaviour.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_DIR="$SCRIPT_DIR"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FIXTURE="$REPO_ROOT/testdata/go-sample"

PASS=0
FAIL=0
FAILED_NAMES=()

# ---------------------------------------------------------------------------
# Tiny test framework
# ---------------------------------------------------------------------------

begin() { printf '  %s ... ' "$1"; }
ok()    { printf 'OK\n';   ((PASS++)); }
ko()    { printf 'FAIL\n'; ((FAIL++)); FAILED_NAMES+=("$CURRENT_NAME"); }

 CURRENT_NAME=""
name()  { CURRENT_NAME="$1"; begin "$1"; }

# run_and_capture — stores stdout in RB_STDOUT, stderr in RB_STDERR, exit in RB_EXIT
run_and_capture() {
    local out err
    out="$(mktemp)" ; err="$(mktemp)"
    "$@" >"$out" 2>"$err" ; RB_EXIT=$? || true
    RB_STDOUT="$(cat "$out")"
    RB_STDERR="$(cat "$err")"
    rm -f "$out" "$err"
}

expect_exit_zero() {
    if [[ "$RB_EXIT" -eq 0 ]]; then ok; else
        printf 'FAIL (exit %d, stderr: %s)\n' "$RB_EXIT" "${RB_STDERR:0:200}"
        ((FAIL++)); FAILED_NAMES+=("$CURRENT_NAME")
    fi
}

expect_exit_nonzero() {
    if [[ "$RB_EXIT" -ne 0 ]]; then ok; else
        printf 'FAIL (expected non-zero exit, got 0)\n'
        ((FAIL++)); FAILED_NAMES+=("$CURRENT_NAME")
    fi
}

expect_stdout_empty() {
    if [[ -z "$RB_STDOUT" ]]; then ok; else
        printf 'FAIL (stdout not empty: %s)\n' "${RB_STDOUT:0:200}"
        ((FAIL++)); FAILED_NAMES+=("$CURRENT_NAME")
    fi
}

expect_stdout_exactly_one_line() {
    local lines
    lines="$(printf '%s\n' "$RB_STDOUT" | wc -l)"
    if [[ "$lines" -eq 1 && -n "$RB_STDOUT" ]]; then ok; else
        printf 'FAIL (stdout lines=%d, got: %s)\n' "$lines" "${RB_STDOUT:0:200}"
        ((FAIL++)); FAILED_NAMES+=("$CURRENT_NAME")
    fi
}

expect_stdout_contains() {
    local needle="$1"
    if [[ "$RB_STDOUT" == *"$needle"* ]]; then ok; else
        printf 'FAIL (stdout missing %q, got: %s)\n' "$needle" "${RB_STDOUT:0:200}"
        ((FAIL++)); FAILED_NAMES+=("$CURRENT_NAME")
    fi
}

expect_file_exists() {
    if [[ -f "$1" ]]; then ok; else
        printf 'FAIL (file missing: %s)\n' "$1"
        ((FAIL++)); FAILED_NAMES+=("$CURRENT_NAME")
    fi
}

# ---------------------------------------------------------------------------
# Stub generator — creates a fake `sunset` CLI with controllable behaviour
# ---------------------------------------------------------------------------

# create_stub <path> <stub_version> [options...]
# Options:
#   --langs "go javascript typescript python"  (default: all four)
#   --no-index          don't create index.md
#   --no-files          don't create files/*.md
#   --index-version X   override sunset_version in index.md (default: stub_version)
#   --no-exec           don't set executable bit
create_stub() {
    local path="$1"
    local stub_version="$2"; shift 2

    local langs="go javascript typescript python"
    local make_index=true
    local make_files=true
    local index_version="$stub_version"
    local exec_bit=true

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --langs)         langs="$2";        shift 2 ;;
            --no-index)      make_index=false;  shift   ;;
            --no-files)      make_files=false;  shift   ;;
            --index-version) index_version="$2"; shift 2 ;;
            --no-exec)       exec_bit=false;    shift   ;;
            *) shift ;;
        esac
    done

    {
        echo '#!/usr/bin/env bash'
        echo 'case "$1" in'
        echo '    version)'
        echo "        echo \"sunset ${stub_version}\""
        echo '        ;;'
        echo '    languages)'
        echo '        echo "Supported languages:"'
        echo '        echo ""'
        echo '        echo "  Language        Extensions"'
        echo '        echo "  --------        ----------"'
        for lang in $langs; do
            local ext=""
            case "$lang" in
                go)         ext=".go"         ;;
                javascript) ext=".js, .jsx"   ;;
                typescript) ext=".ts, .tsx"   ;;
                python)     ext=".py"         ;;
                *)          ext=".txt"        ;;
            esac
            printf '        echo "  %-15s %s"\n' "$lang" "$ext"
        done
        echo '        ;;'
        echo '    parse)'
        echo '        outdir=""'
        echo '        shift'
        echo '        while [[ $# -gt 0 ]]; do'
        echo '            case "$1" in'
        echo '                --output)    outdir="$2";       shift 2 ;;'
        echo '                --output=*)  outdir="${1#--output=}"; shift ;;'
        echo '                *)                              shift   ;;'
        echo '            esac'
        echo '        done'
        echo '        mkdir -p "$outdir/files"'
        if $make_index; then
            printf '        cat > "$outdir/index.md" <<INDEXEOF\n'
            printf -- '---\n'
            printf 'project: sample\n'
            printf 'sunset_version: %s\n' "$index_version"
            printf -- '---\n'
            printf 'INDEXEOF\n'
        fi
        if $make_files; then
            echo '        echo "# main.go" > "$outdir/files/main.go.md"'
        fi
        echo '        exit 0'
        echo '        ;;'
        echo '    *)'
        echo '        echo "unknown command: $1" >&2'
        echo '        exit 1'
        echo '        ;;'
        echo 'esac'
    } > "$path"

    if $exec_bit; then
        chmod +x "$path"
    fi
}

# ---------------------------------------------------------------------------
# Test fixtures
# ---------------------------------------------------------------------------

TEST_ROOT="$(mktemp -d)"
# Go module cache files are stored read-only; chmod before rm in cleanup
trap 'chmod -R u+w "$TEST_ROOT" 2>/dev/null || true; rm -rf "$TEST_ROOT" 2>/dev/null || true' EXIT

GOOD_STUB="$TEST_ROOT/stubs/sunset-good"
mkdir -p "$(dirname "$GOOD_STUB")"
create_stub "$GOOD_STUB" "1.0.1"

# ---------------------------------------------------------------------------
# SMOKE TESTS
# ---------------------------------------------------------------------------

smoke_tests() {
    echo ""
    echo "=== Smoke helper tests ==="

    # 1. Success — good stub, exit zero, no stdout
    name "smoke: success path (good stub)"
    run_and_capture bash "$RELEASE_DIR/smoke.sh" "$GOOD_STUB" "1.0.1" "$FIXTURE" "$TEST_ROOT/smoke-out"
    expect_exit_zero
    name "smoke: no stdout on success"
    expect_stdout_empty

    # 2. Wrong version
    name "smoke: wrong version rejected"
    local bad_ver="$TEST_ROOT/stubs/sunset-wrong-ver"
    create_stub "$bad_ver" "9.9.9"
    run_and_capture bash "$RELEASE_DIR/smoke.sh" "$bad_ver" "1.0.1" "$FIXTURE" "$TEST_ROOT/smoke-out"
    expect_exit_nonzero

    # 3. Missing language
    name "smoke: missing language rejected"
    local missing_lang="$TEST_ROOT/stubs/sunset-missing-lang"
    create_stub "$missing_lang" "1.0.1" --langs "go javascript typescript"
    run_and_capture bash "$RELEASE_DIR/smoke.sh" "$missing_lang" "1.0.1" "$FIXTURE" "$TEST_ROOT/smoke-out"
    expect_exit_nonzero

    # 4. Missing index.md
    name "smoke: missing index.md rejected"
    local no_index="$TEST_ROOT/stubs/sunset-no-index"
    create_stub "$no_index" "1.0.1" --no-index
    run_and_capture bash "$RELEASE_DIR/smoke.sh" "$no_index" "1.0.1" "$FIXTURE" "$TEST_ROOT/smoke-out"
    expect_exit_nonzero

    # 5. No per-file output
    name "smoke: no files/*.md rejected"
    local no_files="$TEST_ROOT/stubs/sunset-no-files"
    create_stub "$no_files" "1.0.1" --no-files
    run_and_capture bash "$RELEASE_DIR/smoke.sh" "$no_files" "1.0.1" "$FIXTURE" "$TEST_ROOT/smoke-out"
    expect_exit_nonzero

    # 6. Wrong sunset_version in index.md
    name "smoke: wrong sunset_version in index.md rejected"
    local bad_sv="$TEST_ROOT/stubs/sunset-bad-sv"
    create_stub "$bad_sv" "1.0.1" --index-version "0.0.1"
    run_and_capture bash "$RELEASE_DIR/smoke.sh" "$bad_sv" "1.0.1" "$FIXTURE" "$TEST_ROOT/smoke-out"
    expect_exit_nonzero

    # 7. Missing arguments
    name "smoke: too few args rejected"
    run_and_capture bash "$RELEASE_DIR/smoke.sh" "$GOOD_STUB" "1.0.1" "$FIXTURE"
    expect_exit_nonzero

    name "smoke: too many args rejected"
    run_and_capture bash "$RELEASE_DIR/smoke.sh" "$GOOD_STUB" "1.0.1" "$FIXTURE" "$TEST_ROOT/smoke-out" "extra"
    expect_exit_nonzero

    # 8. Non-existent executable
    name "smoke: non-existent executable rejected"
    run_and_capture bash "$RELEASE_DIR/smoke.sh" "$TEST_ROOT/nonexistent" "1.0.1" "$FIXTURE" "$TEST_ROOT/smoke-out"
    expect_exit_nonzero
}

# ---------------------------------------------------------------------------
# PACKAGE-AND-VERIFY TESTS
# ---------------------------------------------------------------------------

package_tests() {
    echo ""
    echo "=== Package-and-verify helper tests ==="

    # Source the helper so we can test the internal verify function
    # shellcheck disable=SC1091
    source "$RELEASE_DIR/package-and-verify.sh"

    # Helper to create a tar.gz from a staging dir
    make_archive() {
        local archive="$1" staging="$2"; shift 2
        tar -czf "$archive" -C "$staging" "$@"
    }

    # --- Verify function unit tests (sourceable) ---

    # 1. Verify accepts a valid archive
    name "package: verify accepts valid archive"
    local stage="$TEST_ROOT/pk-stage1"; mkdir -p "$stage"
    create_stub "$stage/sunset" "1.0.1"
    make_archive "$TEST_ROOT/good.tar.gz" "$stage" sunset
    if _sunset_pv_verify_archive "$TEST_ROOT/good.tar.gz" "sunset" 2>/dev/null; then ok; else ko; fi

    # 2. Verify rejects malformed archive
    name "package: verify rejects malformed archive"
    echo "this is not a tarball" > "$TEST_ROOT/malformed.tar.gz"
    if _sunset_pv_verify_archive "$TEST_ROOT/malformed.tar.gz" "sunset" 2>/dev/null; then ko; else ok; fi

    # 3. Verify rejects extra root entry
    name "package: verify rejects extra root entry"
    local stage2="$TEST_ROOT/pk-stage2"; mkdir -p "$stage2"
    create_stub "$stage2/sunset" "1.0.1"
    echo "extra" > "$stage2/extra.txt"
    make_archive "$TEST_ROOT/extra.tar.gz" "$stage2" sunset extra.txt
    if _sunset_pv_verify_archive "$TEST_ROOT/extra.tar.gz" "sunset" 2>/dev/null; then ko; else ok; fi

    # 4. Verify rejects wrong executable name
    name "package: verify rejects wrong executable name"
    local stage3="$TEST_ROOT/pk-stage3"; mkdir -p "$stage3"
    create_stub "$stage3/wrongname" "1.0.1"
    make_archive "$TEST_ROOT/wrongname.tar.gz" "$stage3" wrongname
    if _sunset_pv_verify_archive "$TEST_ROOT/wrongname.tar.gz" "sunset" 2>/dev/null; then ko; else ok; fi

    # 5. Verify rejects lost POSIX execute bit
    name "package: verify rejects lost execute bit"
    local stage4="$TEST_ROOT/pk-stage4"; mkdir -p "$stage4"
    create_stub "$stage4/sunset" "1.0.1" --no-exec
    make_archive "$TEST_ROOT/noexec.tar.gz" "$stage4" sunset
    if _sunset_pv_verify_archive "$TEST_ROOT/noexec.tar.gz" "sunset" 2>/dev/null; then ko; else ok; fi

    # --- End-to-end packaging tests ---

    # 6. Full success path
    name "package: full success path prints one archive path"
    local arch_dir="$TEST_ROOT/archives1"
    run_and_capture bash "$RELEASE_DIR/package-and-verify.sh" \
        "$GOOD_STUB" "1.0.1" "linux" "amd64" "$FIXTURE" "$arch_dir"
    expect_exit_zero
    name "package: stdout is exactly one line"
    expect_stdout_exactly_one_line
    name "package: stdout contains expected archive name"
    expect_stdout_contains "sunset_1.0.1_linux_amd64.tar.gz"
    name "package: archive file exists"
    expect_file_exists "$arch_dir/sunset_1.0.1_linux_amd64.tar.gz"

    # 7. Failure path removes archive
    name "package: failure leaves no archive behind"
    local bad_stub="$TEST_ROOT/stubs/sunset-fail-pkg"
    create_stub "$bad_stub" "9.9.9"  # wrong version → smoke will fail
    local arch_dir2="$TEST_ROOT/archives2"
    run_and_capture bash "$RELEASE_DIR/package-and-verify.sh" \
        "$bad_stub" "1.0.1" "linux" "amd64" "$FIXTURE" "$arch_dir2"
    expect_exit_nonzero
    name "package: no archive left on failure"
    if [[ ! -f "$arch_dir2/sunset_1.0.1_linux_amd64.tar.gz" ]]; then ok; else ko; fi

    # 8. Wrong argument count
    name "package: too few args rejected"
    run_and_capture bash "$RELEASE_DIR/package-and-verify.sh" \
        "$GOOD_STUB" "1.0.1" "linux" "amd64" "$FIXTURE"
    expect_exit_nonzero

    name "package: too many args rejected"
    run_and_capture bash "$RELEASE_DIR/package-and-verify.sh" \
        "$GOOD_STUB" "1.0.1" "linux" "amd64" "$FIXTURE" "$TEST_ROOT/archives3" "extra"
    expect_exit_nonzero
}

# ---------------------------------------------------------------------------
# VERIFY-CONSUMER TESTS
# ---------------------------------------------------------------------------

consumer_tests() {
    echo ""
    echo "=== Verify-consumer helper tests ==="

    # 1. Wrong argument count
    name "consumer: too few args rejected"
    run_and_capture bash "$RELEASE_DIR/verify-consumer.sh" "v1.0.1"
    expect_exit_nonzero

    name "consumer: too many args rejected"
    run_and_capture bash "$RELEASE_DIR/verify-consumer.sh" "v1.0.1" "$TEST_ROOT/work" "extra"
    expect_exit_nonzero

    # 2. Missing env vars
    name "consumer: missing GOCACHE rejected"
    local saved_cache="${GOCACHE:-}"
    unset GOCACHE
    run_and_capture bash "$RELEASE_DIR/verify-consumer.sh" "v1.0.1" "$TEST_ROOT/work1"
    expect_exit_nonzero
    export GOCACHE="$saved_cache"

    name "consumer: missing GOMODCACHE rejected"
    local saved_mod="${GOMODCACHE:-}"
    unset GOMODCACHE
    run_and_capture bash "$RELEASE_DIR/verify-consumer.sh" "v1.0.1" "$TEST_ROOT/work2"
    expect_exit_nonzero
    export GOMODCACHE="$saved_mod"

    name "consumer: missing GOBIN rejected"
    local saved_bin="${GOBIN:-}"
    unset GOBIN
    run_and_capture bash "$RELEASE_DIR/verify-consumer.sh" "v1.0.1" "$TEST_ROOT/work3"
    expect_exit_nonzero
    export GOBIN="$saved_bin"

    # 3. Success path with SUNSET_REPLACE (local checkout)
    name "consumer: success with local replace"
    export GOCACHE="$TEST_ROOT/gocache"
    export GOMODCACHE="$TEST_ROOT/gomodcache"
    export GOBIN="$TEST_ROOT/gobin"
    mkdir -p "$GOCACHE" "$GOMODCACHE" "$GOBIN"
    # Let GOPROXY default — the test needs the standard proxy for transitive deps.
    # The helper itself defaults GOPROXY to "direct" when unset (for CI use).
    run_and_capture env SUNSET_REPLACE="$REPO_ROOT" GOPROXY=https://proxy.golang.org,direct \
        bash "$RELEASE_DIR/verify-consumer.sh" "v1.0.1" "$TEST_ROOT/consumer-ok"
    expect_exit_zero
    name "consumer: no stdout on success"
    expect_stdout_empty

    # 4. Compile mismatch (bad replace path → go build fails)
    name "consumer: compile mismatch rejected"
    run_and_capture env SUNSET_REPLACE="/nonexistent/path/xyz" GOPROXY=direct \
        bash "$RELEASE_DIR/verify-consumer.sh" "v1.0.1" "$TEST_ROOT/consumer-bad"
    expect_exit_nonzero
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    echo "Release helper test suite"
    echo "TEST_ROOT: $TEST_ROOT"
    echo "FIXTURE:   $FIXTURE"

    smoke_tests
    package_tests
    consumer_tests

    echo ""
    echo "==========================================="
    echo "Results: $PASS passed, $FAIL failed"
    if [[ $FAIL -gt 0 ]]; then
        echo "Failed tests:" >&2
        for t in "${FAILED_NAMES[@]}"; do
            echo "  - $t" >&2
        done
        exit 1
    fi
    echo "All tests passed."
}

main "$@"
