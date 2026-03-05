#!/bin/bash
###############################################################################
# POST-EDIT LINT HOOK
# Runs after Write/Edit operations.
#
# If auto_lint_on_edit is enabled in engine.yaml and a lint_command is set,
# runs the linter on the modified file.
#
# Input: Receives tool output via stdin (JSON from Claude Code hooks API)
# Output: Lint results to stderr (informational)
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENGINE_YAML="$REPO_ROOT/engine.yaml"

# Check if auto-lint is enabled
if [ ! -f "$ENGINE_YAML" ]; then
    exit 0
fi

AUTO_LINT=$(grep 'auto_lint_on_edit:' "$ENGINE_YAML" | head -1 | awk '{print $2}' || echo "false")
if [ "$AUTO_LINT" != "true" ]; then
    exit 0
fi

LINT_CMD=$(grep 'lint_command:' "$ENGINE_YAML" | head -1 | sed 's/.*lint_command: *//' | sed 's/ *#.*//' | tr -d '"')
if [ -z "$LINT_CMD" ]; then
    exit 0
fi

# Read the tool output from stdin
INPUT=$(cat)

# Extract file_path
FILE_PATH=$(echo "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//' | sed 's/"$//')

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Run lint command (best effort, don't fail the hook)
cd "$REPO_ROOT"
eval "$LINT_CMD" "$FILE_PATH" 2>&1 | head -20 >&2 || true

exit 0
