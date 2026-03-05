#!/bin/bash
###############################################################################
# RALPH LOOP — Orquestrador
#
# Executa o Ralph em worktree isolado com Skinner Enforcement.
# O motor e centralizado — cada projeto em workspace/ e um repo independente.
#
# Uso:
#   ./ralph-loop.sh ghostfit                   # Rodar no workspace ghostfit
#   ./ralph-loop.sh ghostfit --max-loops 5     # Limitar a 5 loops
#   ./ralph-loop.sh ghostfit --dry-run         # Simular sem executar
#   ./ralph-loop.sh ghostfit --prompt "fix X"  # Task especifica
#
# O primeiro argumento e o nome do workspace (pasta em workspace/).
# Cada workspace e um repo git independente com seu proprio .ralphrc.
###############################################################################

MOTOR_ROOT="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$MOTOR_ROOT/.skinner/skinner.sh" ]; then
    echo "ERROR: Skinner not found at .skinner/skinner.sh"
    exit 1
fi

# First arg must be workspace name
if [ -z "$1" ] || [[ "$1" == --* ]]; then
    echo "ERROR: Workspace name required as first argument."
    echo ""
    echo "Usage: ./ralph-loop.sh <workspace-name> [options]"
    echo ""
    echo "Options:"
    echo "  --max-loops N    Limit to N loops (default: 20)"
    echo "  --dry-run        Simulate without executing"
    echo "  --prompt \"...\"   Custom task prompt"
    echo ""
    echo "Available workspaces:"
    for dir in "$MOTOR_ROOT"/workspace/*/; do
        if [ -d "$dir/.git" ]; then
            name=$(basename "$dir")
            has_ralphrc=""
            [ -f "$dir/.ralphrc" ] && has_ralphrc=" (configured)"
            echo "  - $name$has_ralphrc"
        fi
    done
    exit 1
fi

WORKSPACE_NAME="$1"
shift

PROJECT_DIR="$MOTOR_ROOT/workspace/$WORKSPACE_NAME"

if [ ! -d "$PROJECT_DIR" ]; then
    echo "ERROR: Workspace not found: $PROJECT_DIR"
    echo "Run /setup-workspace $WORKSPACE_NAME to create it."
    exit 1
fi

if [ ! -d "$PROJECT_DIR/.git" ]; then
    echo "ERROR: workspace/$WORKSPACE_NAME/ is not a git repository."
    echo "Each workspace must be an independent git repo."
    echo "Run /setup-workspace $WORKSPACE_NAME to initialize it."
    exit 1
fi

if [ ! -f "$PROJECT_DIR/.ralphrc" ]; then
    echo "ERROR: No .ralphrc found in workspace/$WORKSPACE_NAME/"
    echo "Run /setup-workspace $WORKSPACE_NAME to configure it."
    exit 1
fi

# Pass motor root and project dir to Skinner
export MOTOR_ROOT
export PROJECT_DIR

exec "$MOTOR_ROOT/.skinner/skinner.sh" --workspace "$WORKSPACE_NAME" "$@"
