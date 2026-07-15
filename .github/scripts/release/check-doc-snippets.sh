#!/usr/bin/env bash
#
# check-doc-snippets.sh — Fail if README fenced code blocks differ from the
# canonical install snippet files under docs/snippets/.
#
# Usage:
#   check-doc-snippets.sh [readme] [snippet-root]
#
# Defaults:
#   readme        = README.md
#   snippet-root  = docs/snippets
#
# Each snippet is published in <readme> inside a marked region:
#
#   <!-- snippet: docs/snippets/v1.0.1/install-linux.sh -->
#   ```bash
#   ...verbatim content...
#   ```
#   <!-- /snippet: docs/snippets/v1.0.1/install-linux.sh -->
#
# This script extracts each fenced block and compares it byte-for-byte with
# the source file (trailing newline differences are normalized).  Any mismatch
# — or a snippet file with no corresponding marked block — causes a non-zero
# exit so the discrepancy is caught before promotion.
#
set -uo pipefail

README="${1:-README.md}"
SNIPPET_ROOT="${2:-docs/snippets}"

_fail() { echo "check-doc-snippets: $*" >&2; }

if [[ ! -f "$README" ]]; then
    _fail "readme not found: $README"
    exit 2
fi
if [[ ! -d "$SNIPPET_ROOT" ]]; then
    _fail "snippet root not found: $SNIPPET_ROOT"
    exit 2
fi

# Collect snippet files (relative paths, sorted for deterministic output).
snippets=()
while IFS= read -r -d '' f; do
    snippets+=("$f")
done < <(find "$SNIPPET_ROOT" -type f -print0 | sort -z)

if [[ ${#snippets[@]} -eq 0 ]]; then
    _fail "no snippet files found under $SNIPPET_ROOT"
    exit 2
fi

errors=0
checked=0

for snippet in "${snippets[@]}"; do
    marker_start="<!-- snippet: $snippet -->"
    marker_end="<!-- /snippet: $snippet -->"

    # Extract the fenced-block content for this snippet from the readme.
    # The awk program enables a region between the two markers, then captures
    # the lines between the first pair of ``` fences inside that region.
    extracted="$(awk -v ms="$marker_start" -v me="$marker_end" '
        $0 == ms { region = 1; next }
        $0 == me { region = 0 }
        region && /^```/ {
            if (!fence) { fence = 1; next }
            else        { fence = 0; next }
        }
        region && fence { print }
    ' "$README")"

    if [[ -z "$extracted" ]]; then
        _fail "no fenced block found for snippet: $snippet"
        _fail "  expected markers: $marker_start / $marker_end"
        errors=$((errors + 1))
        continue
    fi

    # Both sides go through command substitution, which strips trailing
    # newlines — so a single missing/extra trailing newline does not cause a
    # false negative.  All other bytes must match exactly.
    file_content="$(cat "$snippet")"

    if [[ "$extracted" != "$file_content" ]]; then
        _fail "fenced block does not match snippet: $snippet"
        _fail "  diff (left = README block, right = snippet file):"
        diff <(printf '%s\n' "$extracted") <(printf '%s\n' "$file_content") \
            | sed 's/^/    /' >&2
        errors=$((errors + 1))
        continue
    fi

    checked=$((checked + 1))
done

if [[ $errors -gt 0 ]]; then
    total=$((checked + errors))
    _fail "$errors of $total snippet(s) out of sync with $README"
    exit 1
fi

echo "check-doc-snippets: OK — $checked snippet(s) match $README"
