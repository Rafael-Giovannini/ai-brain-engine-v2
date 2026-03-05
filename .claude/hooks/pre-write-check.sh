#!/bin/bash
###############################################################################
# PRE-WRITE CHECK HOOK
# Runs before Write/Edit operations.
#
# Checks:
#   1. Protected files — block edits to critical files
#   2. Write without test — warn if editing source without test
#
# Input: Receives tool input via stdin (JSON from Claude Code hooks API)
# Output: Exit 0 = allow, Exit 2 = block with message to stderr
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENGINE_YAML="$REPO_ROOT/engine.yaml"

# Read the tool input from stdin
INPUT=$(cat)

# Extract file_path from the JSON input
FILE_PATH=$(echo "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//' | sed 's/"$//')

if [ -z "$FILE_PATH" ]; then
    exit 0  # Can't determine file, allow
fi

# Normalize to relative path
REL_PATH="${FILE_PATH#$REPO_ROOT/}"

# ─── Check 1: Protected files ──────────────────────────────────────────────
PROTECTED_FILES=(
    "CLAUDE.md"
    "engine.yaml"
    ".skinner/skinner.sh"
)

# Also check patterns from engine.yaml (basic parsing)
if [ -f "$ENGINE_YAML" ]; then
    while IFS= read -r line; do
        pattern=$(echo "$line" | sed 's/.*- "//' | sed 's/".*//' | sed 's/^ *//')
        if [ -n "$pattern" ]; then
            PROTECTED_FILES+=("$pattern")
        fi
    done < <(grep -A 10 'protected_files:' "$ENGINE_YAML" | grep '^ *- "' || true)
fi

for pattern in "${PROTECTED_FILES[@]}"; do
    # Simple glob match
    if [[ "$REL_PATH" == $pattern ]]; then
        echo "BLOCKED: '$REL_PATH' is a protected file. Use --force override if intentional." >&2
        exit 2
    fi
done

# ─── Check 2: Write without test (warning only) ────────────────────────────
# Check if hooks.block_write_without_test is enabled
BLOCK_NO_TEST="false"
if [ -f "$ENGINE_YAML" ]; then
    BLOCK_NO_TEST=$(grep 'block_write_without_test:' "$ENGINE_YAML" | head -1 | awk '{print $2}' || echo "false")
fi

if [ "$BLOCK_NO_TEST" = "true" ]; then
    # Only check source files (not configs, docs, tests themselves)
    if [[ "$REL_PATH" == src/* ]] || [[ "$REL_PATH" == */main/* ]]; then
        # Check if a corresponding test file exists
        FILENAME=$(basename "$REL_PATH" | sed 's/\.[^.]*$//')
        TEST_EXISTS=$(find "$REPO_ROOT/tests" "$REPO_ROOT/src" -name "*${FILENAME}*Test*" -o -name "*${FILENAME}*test*" -o -name "*${FILENAME}*.test.*" 2>/dev/null | head -1)

        if [ -z "$TEST_EXISTS" ]; then
            echo "WARNING: No test found for '$REL_PATH'. Consider writing tests." >&2
            # Don't block, just warn (exit 0)
        fi
    fi
fi

exit 0
