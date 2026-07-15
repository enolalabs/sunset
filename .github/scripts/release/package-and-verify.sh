#!/usr/bin/env bash
#
# package-and-verify.sh — Package a sunset executable into a verified archive.
#
# Usage: package-and-verify.sh <executable> <version> <os> <arch> <fixture> <archive-output-dir>
#
# Creates the archive sunset_<version>_<os>_<arch>.tar.gz in the output dir,
# verifies archive integrity, runs the smoke helper, and prints ONLY the
# absolute verified archive path to stdout.
#
# On failure, exits non-zero with diagnostics on stderr and removes any
# partially-created archive.
#
set -uo pipefail

_usage() {
    echo "usage: package-and-verify.sh <executable> <version> <os> <arch> <fixture> <archive-output-dir>" >&2
}

_fail() {
    echo "package-and-verify: $*" >&2
}

# ---------------------------------------------------------------------------
# _sunset_pv_verify_archive — Internal verification, sourceable for testing.
#
#   _sunset_pv_verify_archive <archive> <expected-root-name>
#
# Returns 0 if the archive is valid, 1 otherwise.
# Diagnostics go to stderr.
# ---------------------------------------------------------------------------
_sunset_pv_verify_archive() {
    local archive="$1"
    local expected_root="$2"

    [[ -f "$archive" ]] || { echo "verify: archive not found: $archive" >&2; return 1; }

    # Check archive integrity
    if ! tar -tzf "$archive" >/dev/null 2>&1; then
        echo "verify: malformed or corrupt archive: $archive" >&2
        return 1
    fi

    # List all entries — exactly one root entry matching expected_root
    local entries
    entries="$(tar -tzf "$archive")" || { echo "verify: cannot list archive entries" >&2; return 1; }

    local root_entries=()
    while IFS= read -r entry; do
        # Extract the top-level path component
        local top="${entry%%/*}"
        # Skip empty lines
        [[ -z "$top" ]] && continue
        # Check if this is a new root entry
        local found=false
        for re in "${root_entries[@]+"${root_entries[@]}"}"; do
            if [[ "$re" == "$top" ]]; then
                found=true
                break
            fi
        done
        if ! $found; then
            root_entries+=("$top")
        fi
    done <<< "$entries"

    if [[ ${#root_entries[@]} -ne 1 ]]; then
        echo "verify: expected exactly 1 root entry, found ${#root_entries[@]}: ${root_entries[*]+"${root_entries[*]}"}" >&2
        return 1
    fi

    if [[ "${root_entries[0]}" != "$expected_root" ]]; then
        echo "verify: expected root entry '$expected_root', found '${root_entries[0]}'" >&2
        return 1
    fi

    # Extract into a temp directory and check permissions
    local extract_tmp
    extract_tmp="$(mktemp -d)" || { echo "verify: cannot create temp dir" >&2; return 1; }

    if ! tar -xzf "$archive" -C "$extract_tmp" 2>/dev/null; then
        rm -rf "$extract_tmp"
        echo "verify: cannot extract archive" >&2
        return 1
    fi

    local extracted_file="$extract_tmp/$expected_root"

    if [[ ! -f "$extracted_file" ]]; then
        rm -rf "$extract_tmp"
        echo "verify: expected file '$expected_root' not found after extraction" >&2
        return 1
    fi

    if [[ ! -x "$extracted_file" ]]; then
        rm -rf "$extract_tmp"
        echo "verify: extracted file is not executable: $expected_root" >&2
        return 1
    fi

    rm -rf "$extract_tmp"
    return 0
}

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------
_sunset_pv_main() {
    local executable="$1"
    local version="$2"
    local os="$3"
    local arch="$4"
    local fixture="$5"
    local archive_dir="$6"

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

    local archive_name="sunset_${version}_${os}_${arch}.tar.gz"
    local archive_path="$archive_dir/$archive_name"

    # Validate inputs
    [[ -x "$executable" ]] || { _fail "executable not found or not executable: $executable"; return 2; }
    [[ -d "$fixture" ]]    || { _fail "fixture directory not found: $fixture"; return 2; }

    # Create output directory if needed
    mkdir -p "$archive_dir" || { _fail "cannot create archive output dir: $archive_dir"; return 2; }

    # Stage: copy executable as 'sunset' into a staging directory
    local stage
    stage="$(mktemp -d)" || { _fail "cannot create staging dir"; return 1; }

    local cleanup_archive=false
    _cleanup() {
        rm -rf "$stage"
        if $cleanup_archive && [[ -f "$archive_path" ]]; then
            rm -f "$archive_path"
        fi
    }

    cp "$executable" "$stage/sunset" || { _fail "cannot copy executable to staging"; _cleanup; return 1; }
    chmod +x "$stage/sunset"

    # Create archive
    if ! tar -czf "$archive_path" -C "$stage" sunset 2>/dev/null; then
        _fail "cannot create archive: $archive_path"
        _cleanup
        return 1
    fi
    cleanup_archive=true

    # Verify archive integrity
    if ! _sunset_pv_verify_archive "$archive_path" "sunset"; then
        _fail "archive verification failed"
        _cleanup
        return 1
    fi

    # Extract and run smoke test
    local smoke_tmp
    smoke_tmp="$(mktemp -d)" || { _fail "cannot create smoke temp dir"; _cleanup; return 1; }

    if ! tar -xzf "$archive_path" -C "$smoke_tmp" 2>/dev/null; then
        rm -rf "$smoke_tmp"
        _fail "cannot extract archive for smoke test"
        _cleanup
        return 1
    fi

    local smoke_out="$smoke_tmp/smoke-out"
    mkdir -p "$smoke_out"

    if ! bash "$script_dir/smoke.sh" "$smoke_tmp/sunset" "$version" "$fixture" "$smoke_out"; then
        rm -rf "$smoke_tmp"
        _fail "smoke test failed on extracted binary"
        _cleanup
        return 1
    fi

    rm -rf "$smoke_tmp"
    rm -rf "$stage"

    # Print ONLY the absolute verified archive path
    local abs_path
    abs_path="$(cd "$archive_dir" && pwd)/$archive_name"
    echo "$abs_path"

    return 0
}

# Run only when executed directly (not sourced for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -ne 6 ]]; then
        _usage
        exit 2
    fi
    _sunset_pv_main "$@" || exit $?
    exit 0
fi
