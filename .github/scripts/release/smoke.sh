#!/usr/bin/env bash
#
# smoke.sh — Run smoke tests against a sunset executable.
#
# Usage: smoke.sh <executable> <version> <fixture> <output-dir>
#
# Writes diagnostics ONLY to stderr.
# Exits zero WITHOUT stdout on success.
# Exits non-zero WITH diagnostics on stderr on failure.
#
set -uo pipefail

_usage() {
    echo "usage: smoke.sh <executable> <version> <fixture> <output-dir>" >&2
    echo "  executable  path to the sunset binary to test" >&2
    echo "  version     exact version string expected (e.g. 1.0.1)" >&2
    echo "  fixture     path to the fixture directory to parse" >&2
    echo "  output-dir  writable directory for temporary working files" >&2
}

_fail() {
    echo "smoke: $*" >&2
    exit 1
}

if [[ $# -ne 4 ]]; then
    _usage
    exit 2
fi

EXECUTABLE="$1"
VERSION="$2"
FIXTURE="$3"
OUTPUT_DIR="$4"

[[ -x "$EXECUTABLE" ]] || _fail "executable not found or not executable: $EXECUTABLE"
[[ -d "$FIXTURE" ]]    || _fail "fixture directory not found: $FIXTURE"
mkdir -p "$OUTPUT_DIR" || _fail "cannot create output directory: $OUTPUT_DIR"

REQUIRED_LANGS=("go" "javascript" "typescript" "python")

# 1. sunset version → exits zero, prints exact version
version_output="$("$EXECUTABLE" version 2>&1)" || _fail "'sunset version' exited non-zero: $version_output"
expected="sunset ${VERSION}"
if [[ "$version_output" != "$expected" ]]; then
    _fail "version mismatch: expected '$expected', got '$version_output'"
fi

# 2. sunset languages → exits zero, lists all four languages
langs_output="$("$EXECUTABLE" languages 2>&1)" || _fail "'sunset languages' exited non-zero: $langs_output"
for lang in "${REQUIRED_LANGS[@]}"; do
    if ! grep -qw "$lang" <<< "$langs_output"; then
        _fail "language '$lang' not found in 'sunset languages' output"
    fi
done

# 3. sunset parse --no-cache --quiet --output <tmp> <fixture>
parse_tmp="$(mktemp -d "${OUTPUT_DIR}/smoke.XXXXXX")" || _fail "could not create temp directory"
trap 'rm -rf "$parse_tmp"' EXIT

parse_err="$(mktemp)"
if ! "$EXECUTABLE" parse --no-cache --quiet --output "$parse_tmp" "$FIXTURE" >/dev/null 2>"$parse_err"; then
    local_err="$(cat "$parse_err")"
    rm -f "$parse_err"
    _fail "'sunset parse' exited non-zero: $local_err"
fi
rm -f "$parse_err"

# 4. Output contains index.md and at least one files/*.md
[[ -f "$parse_tmp/index.md" ]] || _fail "index.md not found in parse output"
shopt -s nullglob
file_outputs=("$parse_tmp/files/"*.md)
shopt -u nullglob
if [[ ${#file_outputs[@]} -eq 0 ]]; then
    _fail "no files/*.md found in parse output"
fi

# 5. index.md contains sunset_version: <exact-version>
if ! grep -q "^sunset_version: ${VERSION}$" "$parse_tmp/index.md"; then
    _fail "index.md does not contain 'sunset_version: ${VERSION}'"
fi

exit 0
