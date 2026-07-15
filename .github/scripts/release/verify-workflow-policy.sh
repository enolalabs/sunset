#!/usr/bin/env bash
#
# verify-workflow-policy.sh — Enforce the release-workflow pinning policy.
#
# Usage:
#   verify-workflow-policy.sh [--reject-write] <workflow.yml> [<workflow.yml>...]
#
# Rules (each violation causes a non-zero exit, diagnostics to stderr):
#
#  1. Every non-local `uses:` entry must point at exactly one of the four
#     allowlisted official actions at the listed 40-hex SHA. Local composite
#     actions (`uses: ./...`) are permitted.
#  2. Every `actions/checkout@*` step MUST set `persist-credentials: false`
#     in its `with:` block.
#  3. Every job (declared immediately under `jobs:`) MUST declare a finite
#     `timeout-minutes`.
#  4. The strings `softprops` and `goreleaser` (case-insensitive) MUST NOT
#     appear anywhere in either workflow file.
#  5. With `--reject-write`, no `permissions:` block (job- or workflow-level)
#     may grant any `write` capability. Use this for the read-only validation
#     workflow.
#
# Exits 0 on success with a one-line OK message on stdout.
#
set -uo pipefail

REJECT_WRITE=false
FILES=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --reject-write) REJECT_WRITE=true; shift ;;
        --help|-h)
            sed -n '3,29p' "$0"
            exit 0
            ;;
        --*) echo "verify-workflow-policy: unknown option: $1" >&2; exit 2 ;;
        *)  FILES+=("$1"); shift ;;
    esac
done

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "verify-workflow-policy: no input files" >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# Allowlisted actions: name -> exact 40-hex SHA.
# ---------------------------------------------------------------------------
declare -A ALLOWED_SHA=(
    [actions/checkout]=34e114876b0b11c390a56381ad16ebd13914f8d5
    [actions/setup-go]=40f1582b2485089dde7abd97c1529aa768e1baff
    [actions/upload-artifact]=ea165f8d65b6e75b540449e92b4886f43607fa02
    [actions/download-artifact]=d3f86a106a0bac45b974a628896c90dbdf5c8093
)
readonly ALLOWED_SHA

HEX_RE='^[0-9a-f]{40}$'

errors=0
checked_files=0

_fail() {
    echo "verify-workflow-policy: $*" >&2
    errors=$((errors + 1))
}

# ---------------------------------------------------------------------------
# Validate a single `uses:` reference.
# ---------------------------------------------------------------------------
validate_uses() {
    local ref="$1" file="$2" line_no="$3"
    # Strip surrounding quotes.
    ref="${ref#\"}"; ref="${ref#\'}"
    ref="${ref%\"}"; ref="${ref%\'}"
    # Strip trailing inline comment.
    ref="${ref%% #*}"
    ref="${ref%%	#*}"
    # Strip trailing whitespace.
    ref="$(printf '%s' "$ref" | sed -e 's/[[:space:]]*$//')"

    # Local composite action.
    if [[ "$ref" == ./* ]]; then
        return 0
    fi

    # Must contain exactly one '@'.
    if [[ "$ref" != *@* || "$ref" == *@*@* ]]; then
        _fail "$file:$line_no: malformed uses: '$ref' (expected name@sha)"
        return 1
    fi
    local name="${ref%@*}"
    local sha="${ref##*@}"

    # Unknown action.
    if [[ -z "${ALLOWED_SHA[$name]+present}" ]]; then
        _fail "$file:$line_no: action '$name' is not on the allowlist"
        return 1
    fi

    local expected="${ALLOWED_SHA[$name]}"
    if [[ "$sha" != "$expected" ]]; then
        if [[ "$sha" =~ ^v[0-9] || "$sha" == "latest" || "$sha" == "main" || "$sha" == "master" ]]; then
            _fail "$file:$line_no: action '$name' uses moving ref '$sha' (must be exact SHA $expected)"
        elif [[ "${#sha}" -ge 7 && "$sha" =~ ^[0-9a-f]+$ && "${#sha}" -lt 40 ]]; then
            _fail "$file:$line_no: action '$name' uses short SHA '$sha' (must be exact 40-hex SHA $expected)"
        elif [[ ! "$sha" =~ $HEX_RE ]]; then
            _fail "$file:$line_no: action '$name' uses non-SHA ref '$sha' (must be exact 40-hex SHA $expected)"
        elif [[ "${#sha}" -eq 40 ]]; then
            _fail "$file:$line_no: action '$name' uses wrong SHA '$sha' (must be $expected)"
        else
            _fail "$file:$line_no: action '$name' uses invalid ref '$sha' (must be exact 40-hex SHA $expected)"
        fi
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Per-job timeout enforcement. Emits "<jobname>\t<0|1>" per job, where the
# flag is 1 if a `timeout-minutes:` line appears at any indent inside the
# job block.
# ---------------------------------------------------------------------------
emit_job_timeouts() {
    awk '
        BEGIN { in_jobs = 0; cur = ""; has_to = 0 }
        /^[^[:space:]]/ {
            if (in_jobs) {
                if (cur != "") { print cur "\t" (has_to ? "1" : "0") }
                cur = ""; has_to = 0
            }
            if ($0 ~ /^jobs:/) { in_jobs = 1; next }
            in_jobs = 0
            next
        }
        in_jobs {
            # A job definition: exactly 2 spaces, identifier, then ":".
            if (match($0, /^  [A-Za-z0-9_.-]+:/)) {
                if (cur != "") { print cur "\t" (has_to ? "1" : "0") }
                cur = substr($0, RSTART + 2, RLENGTH - 3)
                gsub(/[[:space:]]+$/, "", cur)
                has_to = 0
            } else if (cur != "" && $0 ~ /^[[:space:]]*timeout-minutes:/) {
                has_to = 1
            }
        }
        END {
            if (in_jobs && cur != "") { print cur "\t" (has_to ? "1" : "0") }
        }
    ' "$1"
}

# ---------------------------------------------------------------------------
# Walk one file: action pins, checkout isolation, job timeouts, forbidden
# references, optional write-permission rejection.
# ---------------------------------------------------------------------------
validate_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        _fail "file not found: $file"
        return 1
    fi
    checked_files=$((checked_files + 1))

    # Rule 4: forbidden references anywhere in the file.
    local lc
    lc="$(tr '[:upper:]' '[:lower:]' < "$file")"
    if printf '%s' "$lc" | grep -q 'softprops'; then
        _fail "$file: forbidden reference to 'softprops'"
    fi
    if printf '%s' "$lc" | grep -q 'goreleaser'; then
        _fail "$file: forbidden reference to 'goreleaser'"
    fi

    # Rule 5 (optional): reject any write permission.
    if $REJECT_WRITE; then
        if grep -Eq ':[[:space:]]*write([[:space:]]|$)' "$file" \
           || grep -Eqi 'permissions:[[:space:]]*write-all' "$file"; then
            _fail "$file: write permission forbidden in --reject-write mode"
        fi
    fi

    # Rule 1 + Rule 2: walk every line, track uses: and the with: block that
    # follows it. We rely on indentation: a `with:` block ends when we see a
    # line whose indent is less than or equal to the `with:` keyword's.
    local lineno=0
    local with_indent=-1
    local pending_action=""
    local pending_uses_line=""
    local pending_persist=false

    flush_pending() {
        if [[ -n "$pending_action" ]]; then
            if [[ "$pending_action" == "actions/checkout" ]] && ! $pending_persist; then
                _fail "$file:$pending_uses_line: actions/checkout step missing 'persist-credentials: false'"
            fi
        fi
        pending_action=""
        pending_uses_line=""
        pending_persist=false
        with_indent=-1
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$((lineno + 1))
        # Skip blank lines.
        if [[ -z "${line//[[:space:]]/}" ]]; then
            continue
        fi
        # Compute indentation.
        local leading="${line%%[![:space:]]*}"
        local indent=${#leading}
        local stripped="${line#"${leading}"}"
        # Skip full-line comments.
        if [[ "$stripped" == \#* ]]; then
            continue
        fi

        # If we have a pending uses: and the current line's indent is <= the
        # with: block's indent, the with: block has ended.
        if [[ -n "$pending_action" && $with_indent -ge 0 && $indent -le $with_indent ]]; then
            # But only if this isn't another key inside the same with: block.
            # Keys inside with: are at indent > with_indent. So <= means we
            # left the block.
            flush_pending
        fi

        # Strip the leading "- " sequence list marker from step lines.
        if [[ "$stripped" =~ ^-[[:space:]]*(.*)$ ]]; then
            stripped="${BASH_REMATCH[1]}"
        fi

        # Match `uses:` anywhere in the step.
        if [[ "$stripped" =~ ^(uses:)[[:space:]]*(.+)$ ]]; then
            # If a previous uses: was still open, flush it first.
            flush_pending
            local ref="${BASH_REMATCH[2]}"
            pending_uses_line="$lineno"
            pending_persist=false
            local nm="${ref%%@*}"
            nm="${nm#\"}"; nm="${nm#\'}"
            nm="${nm%% *}"; nm="${nm%%	*}"
            pending_action="$nm"
            with_indent=-1
            # Clean the ref before validating.
            local clean_ref="${ref%% #*}"
            clean_ref="${clean_ref%%	#*}"
            clean_ref="$(printf '%s' "$clean_ref" | sed -e 's/[[:space:]]*$//')"
            validate_uses "$clean_ref" "$file" "$lineno" || true
            continue
        fi

        # If we are inside a with: block of a pending uses: step.
        if [[ -n "$pending_action" ]]; then
            local step_body="$stripped"
            if [[ "$step_body" =~ ^-[[:space:]]*(.*)$ ]]; then
                step_body="${BASH_REMATCH[1]}"
            fi
            if [[ "$step_body" =~ ^(with):[[:space:]]*$ ]]; then
                with_indent="$indent"
                continue
            fi
            if [[ "$step_body" =~ ^persist-credentials:[[:space:]]*false ]]; then
                pending_persist=true
            fi
        fi
    done < "$file"

    # Flush the last pending step.
    flush_pending

    # Rule 3: per-job timeout enforcement.
    local tmp
    tmp="$(mktemp)"
    emit_job_timeouts "$file" > "$tmp"
    while IFS=$'\t' read -r jn ht; do
        [[ -z "$jn" ]] && continue
        if [[ "$ht" != "1" ]]; then
            _fail "$file: job '$jn' is missing timeout-minutes"
        fi
    done < "$tmp"
    rm -f "$tmp"
}

for f in "${FILES[@]}"; do
    validate_file "$f"
done

if [[ $errors -gt 0 ]]; then
    echo "verify-workflow-policy: $errors error(s) across $checked_files file(s)" >&2
    exit 1
fi

echo "verify-workflow-policy: OK — $checked_files file(s) compliant"
