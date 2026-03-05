#!/bin/bash
###############################################################################
# RALPH LOOP — Orquestrador
#
# Executa o Ralph em worktree isolado com Skinner Enforcement.
# Uso:
#   ./ralph-loop.sh ghostfit                   # Rodar no workspace ghostfit
#   ./ralph-loop.sh ghostfit --max-loops 5     # Limitar a 5 loops
#   ./ralph-loop.sh ghostfit --dry-run         # Simular sem executar
#   ./ralph-loop.sh ghostfit --prompt "fix X"  # Task especifica
#
# O primeiro argumento e o nome do workspace (pasta em workspace/).
# Cada workspace tem seu proprio .ralphrc e .ralph/ com configs do projeto.
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$SCRIPT_DIR/.skinner/skinner.sh" ]; then
    echo "ERROR: Skinner not found at .skinner/skinner.sh"
    exit 1
fi

# First arg must be workspace name
if [ -z "$1" ] || [[ "$1" == --* ]]; then
    echo "ERROR: Workspace name required as first argument."
    echo ""
    echo "Usage: ./ralph-loop.sh <workspace-name> [options]"
    echo ""
    echo "Available workspaces:"
    for dir in "$SCRIPT_DIR"/workspace/*/; do
        if [ -f "$dir/.ralphrc" ]; then
            name=$(basename "$dir")
            echo "  - $name"
        fi
    done
    exit 1
fi

WORKSPACE_NAME="$1"
shift

WORKSPACE_DIR="$SCRIPT_DIR/workspace/$WORKSPACE_NAME"

if [ ! -d "$WORKSPACE_DIR" ]; then
    echo "ERROR: Workspace not found: $WORKSPACE_DIR"
    exit 1
fi

if [ ! -f "$WORKSPACE_DIR/.ralphrc" ]; then
    echo "ERROR: No .ralphrc found in workspace/$WORKSPACE_NAME/"
    echo "Run ralph configuration for this workspace first."
    exit 1
fi

exec "$SCRIPT_DIR/.skinner/skinner.sh" --workspace "$WORKSPACE_NAME" "$@"
