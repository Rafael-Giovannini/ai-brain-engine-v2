#!/bin/bash
###############################################################################
# SKINNER ENFORCEMENT ENGINE v2
# Controle de qualidade para o loop autonomo do Ralph.
#
# Evolucao do v1 com:
#   - Leitura de engine.yaml para flags de camadas
#   - Integracao com VIGIL (memoria comportamental)
#   - Suporte a Langfuse tracing (quando habilitado)
#   - Testes de arquitetura como gate (quando habilitado)
#   - Mutation testing como gate (quando habilitado)
#
# Responsabilidades:
#   1. Criar worktree isolado para Ralph trabalhar
#   2. Commit atomico apos cada loop bem-sucedido
#   3. Deteccao de erro circular / alucinacao → auto-revert
#   4. Circuit breaker → parar Ralph se nao houver progresso
#   5. Log de auditoria de todas as acoes
#   6. VIGIL: registrar erros e adaptar prompts (v2)
#
# Uso:
#   ./skinner.sh --workspace ghostfit [--dry-run] [--max-loops N] [--prompt "task"]
###############################################################################

set -euo pipefail

# ─── Config ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Parse args
WORKSPACE_NAME=""
DRY_RUN=false
CUSTOM_PROMPT=""
MAX_LOOPS_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace) WORKSPACE_NAME="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --max-loops) MAX_LOOPS_ARG="$2"; shift 2 ;;
        --prompt) CUSTOM_PROMPT="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

# ─── Engine Config ─────────────────────────────────────────────────────────
# Read engine.yaml for layer flags (basic YAML parsing via grep/sed)
ENGINE_YAML="$REPO_ROOT/engine.yaml"

engine_get() {
    local key="$1"
    local default="$2"
    if [ -f "$ENGINE_YAML" ]; then
        local value
        value=$(grep -E "^\s+${key}:" "$ENGINE_YAML" | head -1 | sed 's/.*: *//' | sed 's/ *#.*//' | tr -d '"' || true)
        echo "${value:-$default}"
    else
        echo "$default"
    fi
}

# Layer flags
VIGIL_ENABLED=$(engine_get "enabled" "true" | head -1)
# More precise parsing for specific layers
is_layer_enabled() {
    local layer="$1"
    if [ -f "$ENGINE_YAML" ]; then
        # Find the layer section and check its enabled flag
        awk "/^  ${layer}:/{found=1} found && /enabled:/{print \$2; exit}" "$ENGINE_YAML" | tr -d ' '
    else
        echo "false"
    fi
}

VIGIL_ENABLED=$(is_layer_enabled "vigil")
ARCHUNIT_ENABLED=$(is_layer_enabled "archunit")
MUTAHUNTER_ENABLED=$(is_layer_enabled "mutahunter")
LANGFUSE_ENABLED=$(is_layer_enabled "langfuse")

# ─── Workspace Config ──────────────────────────────────────────────────────
if [ -n "$WORKSPACE_NAME" ]; then
    WORKSPACE_DIR="$REPO_ROOT/workspace/$WORKSPACE_NAME"
    RALPHRC="$WORKSPACE_DIR/.ralphrc"
    RALPH_DIR="$WORKSPACE_DIR/.ralph"
else
    RALPHRC="$REPO_ROOT/.ralphrc"
    RALPH_DIR="$REPO_ROOT/.ralph"
fi

if [ -f "$RALPHRC" ]; then
    source "$RALPHRC"
else
    echo "ERROR: No .ralphrc found at $RALPHRC"
    exit 1
fi

# Defaults (overridden by .ralphrc or engine.yaml)
PROJECT_NAME="${PROJECT_NAME:-AI-Brain}"
PROJECT_ROOT="${PROJECT_ROOT:-workspace/$WORKSPACE_NAME}"
CLAUDE_CODE_CMD="${CLAUDE_CODE_CMD:-claude}"
CB_NO_PROGRESS_THRESHOLD="${CB_NO_PROGRESS_THRESHOLD:-3}"
CB_SAME_ERROR_THRESHOLD="${CB_SAME_ERROR_THRESHOLD:-5}"
MAX_LOOPS="${MAX_LOOPS_ARG:-${MAX_LOOPS:-20}}"

# ─── State tracking ─────────────────────────────────────────────────────────
WORKTREE_DIR=""
WORKTREE_BRANCH=""
LOG_DIR="$REPO_ROOT/.skinner/logs"
[ -n "$WORKSPACE_NAME" ] && LOG_DIR="$REPO_ROOT/.skinner/logs/$WORKSPACE_NAME"
LOG_FILE="$LOG_DIR/session-$(date +%Y%m%d-%H%M%S).log"
MEMORY_DIR="$REPO_ROOT/.skinner/memory"
NO_PROGRESS_COUNT=0
LAST_ERROR=""
SAME_ERROR_COUNT=0
LOOP_COUNT=0
TOTAL_TASKS_COMPLETED=0
LAST_GOOD_COMMIT=""

# ─── Logging ─────────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$MEMORY_DIR"

log() {
    local level="$1"; shift
    local msg="[$(date '+%H:%M:%S')] [$level] $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

log_separator() {
    echo "────────────────────────────────────────────────────" | tee -a "$LOG_FILE"
}

# ─── VIGIL: Behavioral Memory ─────────────────────────────────────────────
VIGIL_FILE="$MEMORY_DIR/vigil.jsonl"

vigil_record_error() {
    local error_type="$1"
    local error_msg="$2"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    if [ "$VIGIL_ENABLED" = "true" ]; then
        echo "{\"timestamp\":\"$timestamp\",\"type\":\"$error_type\",\"message\":\"$error_msg\",\"workspace\":\"${WORKSPACE_NAME:-root}\",\"loop\":$LOOP_COUNT}" >> "$VIGIL_FILE"
        log "VIGIL" "Recorded error: [$error_type] $error_msg"
    fi
}

vigil_get_context() {
    # Return top N most recent/relevant errors for prompt injection
    if [ "$VIGIL_ENABLED" = "true" ] && [ -f "$VIGIL_FILE" ]; then
        local max_errors
        max_errors=$(engine_get "max_context_errors" "5")
        local workspace_filter="${WORKSPACE_NAME:-root}"

        # Get recent errors for this workspace, deduplicate by message, take top N
        grep "\"workspace\":\"$workspace_filter\"" "$VIGIL_FILE" 2>/dev/null | \
            tail -50 | \
            sort -t'"' -k8 -u | \
            tail -"$max_errors" | \
            while IFS= read -r line; do
                local msg
                msg=$(echo "$line" | sed 's/.*"message":"\([^"]*\)".*/\1/')
                local type
                type=$(echo "$line" | sed 's/.*"type":"\([^"]*\)".*/\1/')
                echo "- [$type] $msg"
            done
    fi
}

vigil_inject_prompt() {
    local base_prompt="$1"
    local context
    context=$(vigil_get_context)

    if [ -n "$context" ]; then
        echo "$base_prompt

## VIGIL: Known Issues (avoid repeating these)
The following errors have occurred in recent sessions. Be aware and avoid them:
$context"
    else
        echo "$base_prompt"
    fi
}

# ─── Worktree Management ────────────────────────────────────────────────────
create_worktree() {
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local wt_name="${WORKSPACE_NAME:-ralph}"
    WORKTREE_BRANCH="ralph/$wt_name-$timestamp"
    WORKTREE_DIR="$REPO_ROOT/.claude/worktrees/$wt_name-$timestamp"

    log "INFO" "Creating worktree: $WORKTREE_BRANCH"
    log "INFO" "Location: $WORKTREE_DIR"

    mkdir -p "$(dirname "$WORKTREE_DIR")"
    git -C "$REPO_ROOT" worktree add -b "$WORKTREE_BRANCH" "$WORKTREE_DIR" HEAD

    # Copy workspace .ralph/ into worktree root
    if [ -d "$RALPH_DIR" ]; then
        cp -r "$RALPH_DIR" "$WORKTREE_DIR/.ralph"
        log "INFO" "Copied .ralph/ from workspace/$WORKSPACE_NAME/"
    fi

    # Copy workspace .ralphrc into worktree root
    if [ -f "$RALPHRC" ]; then
        cp "$RALPHRC" "$WORKTREE_DIR/.ralphrc"
    fi

    # Copy CLAUDE.md if it exists at repo root
    if [ -f "$REPO_ROOT/CLAUDE.md" ]; then
        cp "$REPO_ROOT/CLAUDE.md" "$WORKTREE_DIR/CLAUDE.md"
    fi

    # Copy engine.yaml if it exists
    if [ -f "$REPO_ROOT/engine.yaml" ]; then
        cp "$REPO_ROOT/engine.yaml" "$WORKTREE_DIR/engine.yaml"
    fi

    log "INFO" "Worktree created successfully"
    LAST_GOOD_COMMIT=$(git -C "$WORKTREE_DIR" rev-parse HEAD)
    log "INFO" "Base commit: $LAST_GOOD_COMMIT"
}

cleanup_worktree() {
    if [ -n "$WORKTREE_DIR" ] && [ -d "$WORKTREE_DIR" ]; then
        local changes=$(git -C "$WORKTREE_DIR" diff --stat HEAD 2>/dev/null || true)
        local current_branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)
        if [ -n "$changes" ]; then
            log "WARN" "Uncommitted changes in worktree — leaving for review"
            log "INFO" "Worktree preserved at: $WORKTREE_DIR"
            log "INFO" "Branch: $WORKTREE_BRANCH"
            log "INFO" "To merge: git merge $WORKTREE_BRANCH"
            log "INFO" "To remove: git worktree remove $WORKTREE_DIR"
        else
            log "INFO" "No uncommitted changes. Review commits before merging."
            log "INFO" "Worktree at: $WORKTREE_DIR"
            log "INFO" "To merge: git checkout $current_branch && git merge $WORKTREE_BRANCH"
            log "INFO" "To discard: git worktree remove $WORKTREE_DIR && git branch -D $WORKTREE_BRANCH"
        fi
    fi
}

# ─── Skinner Actions ────────────────────────────────────────────────────────
skinner_commit() {
    local msg="$1"
    if [ "$DRY_RUN" = true ]; then
        log "DRY-RUN" "Would commit: $msg"
        return 0
    fi

    cd "$WORKTREE_DIR"
    local staged=$(git diff --cached --stat)
    local unstaged=$(git diff --stat)
    local untracked=$(git ls-files --others --exclude-standard)

    if [ -z "$staged" ] && [ -z "$unstaged" ] && [ -z "$untracked" ]; then
        log "SKIP" "Nothing to commit"
        return 0
    fi

    # Stage all changes in PROJECT_ROOT and fix_plan
    git add "$PROJECT_ROOT/" .ralph/fix_plan.md 2>/dev/null || true

    staged=$(git diff --cached --stat)
    if [ -z "$staged" ]; then
        log "SKIP" "Nothing staged to commit"
        return 0
    fi

    git commit -m "$(cat <<EOF
[ralph] $msg

Skinner-Enforcement: auto-commit
Project: $PROJECT_NAME | Loop: $LOOP_COUNT | Tasks-this-session: $TOTAL_TASKS_COMPLETED
EOF
    )"

    LAST_GOOD_COMMIT=$(git rev-parse HEAD)
    log "COMMIT" "$(git log --oneline -1)"
    log "INFO" "New checkpoint: $LAST_GOOD_COMMIT"
}

skinner_revert() {
    local reason="$1"
    if [ "$DRY_RUN" = true ]; then
        log "DRY-RUN" "Would revert to: $LAST_GOOD_COMMIT ($reason)"
        return 0
    fi

    log "REVERT" "Reverting to last good commit: $LAST_GOOD_COMMIT"
    log "REVERT" "Reason: $reason"

    cd "$WORKTREE_DIR"
    git reset --hard "$LAST_GOOD_COMMIT"

    # Record in VIGIL
    vigil_record_error "REVERT" "$reason"

    log "REVERT" "Reverted successfully"
}

# ─── Parse Ralph Status ─────────────────────────────────────────────────────
parse_ralph_status() {
    local output="$1"

    local status_block=$(echo "$output" | sed -n '/---RALPH_STATUS---/,/---END_RALPH_STATUS---/p')

    if [ -z "$status_block" ]; then
        echo "STATUS=UNKNOWN"
        echo "TASKS_COMPLETED_THIS_LOOP=0"
        echo "TESTS_STATUS=NOT_RUN"
        echo "EXIT_SIGNAL=false"
        echo "RECOMMENDATION=No status block found"
        return
    fi

    echo "$status_block" | grep -E '^(STATUS|TASKS_COMPLETED_THIS_LOOP|FILES_MODIFIED|TESTS_STATUS|WORK_TYPE|EXIT_SIGNAL|RECOMMENDATION):' | sed 's/: */=/' | sed 's/ *$//'
}

# ─── Circuit Breaker ────────────────────────────────────────────────────────
check_circuit_breaker() {
    local tasks_completed="$1"
    local test_status="$2"
    local exit_signal="$3"
    local recommendation="$4"

    # Exit signal from Ralph
    if [ "$exit_signal" = "true" ]; then
        log "CIRCUIT" "Ralph requested exit: $recommendation"
        return 1
    fi

    # No progress detection
    if [ "$tasks_completed" -eq 0 ] 2>/dev/null; then
        NO_PROGRESS_COUNT=$((NO_PROGRESS_COUNT + 1))
        log "WARN" "No progress detected ($NO_PROGRESS_COUNT/$CB_NO_PROGRESS_THRESHOLD)"
        vigil_record_error "NO_PROGRESS" "Loop $LOOP_COUNT: $recommendation"
    else
        NO_PROGRESS_COUNT=0
    fi

    if [ "$NO_PROGRESS_COUNT" -ge "$CB_NO_PROGRESS_THRESHOLD" ]; then
        log "CIRCUIT" "No progress for $CB_NO_PROGRESS_THRESHOLD consecutive loops"
        vigil_record_error "CIRCUIT_BREAKER" "No progress for $CB_NO_PROGRESS_THRESHOLD loops"
        return 1
    fi

    # Same error detection
    if [ "$test_status" = "FAILING" ]; then
        if [ "$recommendation" = "$LAST_ERROR" ] && [ -n "$LAST_ERROR" ]; then
            SAME_ERROR_COUNT=$((SAME_ERROR_COUNT + 1))
            log "WARN" "Same error repeated ($SAME_ERROR_COUNT/$CB_SAME_ERROR_THRESHOLD)"
        else
            SAME_ERROR_COUNT=1
            LAST_ERROR="$recommendation"
        fi

        if [ "$SAME_ERROR_COUNT" -ge "$CB_SAME_ERROR_THRESHOLD" ]; then
            log "CIRCUIT" "Same error repeated $CB_SAME_ERROR_THRESHOLD times — hallucination detected"
            vigil_record_error "HALLUCINATION" "Same error $CB_SAME_ERROR_THRESHOLD times: $LAST_ERROR"
            skinner_revert "Circular error: $LAST_ERROR"
            return 1
        fi
    else
        SAME_ERROR_COUNT=0
        LAST_ERROR=""
    fi

    return 0
}

# ─── Gate Checks (v2) ───────────────────────────────────────────────────────
run_gate_checks() {
    local passed=true

    # ArchUnit gate
    if [ "$ARCHUNIT_ENABLED" = "true" ]; then
        log "GATE" "Running architecture tests..."
        # TODO: Integrate with project-specific arch test runner
        # For now, log that it would run
        log "GATE" "ArchUnit gate: SKIPPED (not yet configured for this project)"
    fi

    # MutaHunter gate
    if [ "$MUTAHUNTER_ENABLED" = "true" ]; then
        log "GATE" "Running mutation testing..."
        # TODO: Integrate with MutaHunter
        log "GATE" "MutaHunter gate: SKIPPED (not yet configured for this project)"
    fi

    if [ "$passed" = true ]; then
        return 0
    else
        return 1
    fi
}

# ─── Ralph Invocation ───────────────────────────────────────────────────────
run_ralph_loop() {
    local prompt="Follow .ralph/fix_plan.md. Pick the next uncompleted task and implement it. ONE task only."
    if [ -n "$CUSTOM_PROMPT" ]; then
        prompt="$CUSTOM_PROMPT"
    fi

    # VIGIL: inject behavioral memory into prompt
    prompt=$(vigil_inject_prompt "$prompt")

    cd "$WORKTREE_DIR"

    if [ "$DRY_RUN" = true ]; then
        log "DRY-RUN" "Would run: $CLAUDE_CODE_CMD --print \"$prompt\""
        echo "STATUS=IN_PROGRESS"
        echo "TASKS_COMPLETED_THIS_LOOP=1"
        echo "TESTS_STATUS=PASSING"
        echo "EXIT_SIGNAL=false"
        echo "RECOMMENDATION=dry run"
        return 0
    fi

    local -a cmd_args=("--print")

    # Append system prompt from .ralph/PROMPT.md
    if [ -f ".ralph/PROMPT.md" ]; then
        cmd_args+=("--append-system-prompt" "$(cat .ralph/PROMPT.md)")
    fi

    # Allowed tools from .ralphrc
    if [ -n "${ALLOWED_TOOLS:-}" ]; then
        cmd_args+=("--allowedTools" "$ALLOWED_TOOLS")
    fi

    cmd_args+=("-p" "$prompt")

    log "INFO" "Running: $CLAUDE_CODE_CMD --print -p '<prompt>' (${#cmd_args[@]} args)"

    local output
    output=$(unset CLAUDECODE; "$CLAUDE_CODE_CMD" "${cmd_args[@]}" 2>&1) || true

    echo "$output" >> "$LOG_FILE"

    parse_ralph_status "$output"
}

# ─── Main Loop ───────────────────────────────────────────────────────────────
main() {
    log_separator
    log "INFO" "SKINNER ENFORCEMENT ENGINE v2 — $PROJECT_NAME"
    log "INFO" "Workspace: ${WORKSPACE_NAME:-root} | Max loops: $MAX_LOOPS | Dry run: $DRY_RUN"
    log "INFO" "Layers: VIGIL=$VIGIL_ENABLED | ArchUnit=$ARCHUNIT_ENABLED | MutaHunter=$MUTAHUNTER_ENABLED | Langfuse=$LANGFUSE_ENABLED"
    log_separator

    create_worktree

    trap cleanup_worktree EXIT

    while [ "$LOOP_COUNT" -lt "$MAX_LOOPS" ]; do
        LOOP_COUNT=$((LOOP_COUNT + 1))
        log_separator
        log "INFO" "=== LOOP $LOOP_COUNT/$MAX_LOOPS ==="

        # Run Ralph
        log "INFO" "Invoking Ralph..."
        local ralph_output
        ralph_output=$(run_ralph_loop)

        # Parse status
        local status="" tasks_completed="0" tests_status="NOT_RUN" exit_signal="false" recommendation=""

        while IFS='=' read -r key value; do
            case "$key" in
                STATUS) status="$value" ;;
                TASKS_COMPLETED_THIS_LOOP) tasks_completed="$value" ;;
                TESTS_STATUS) tests_status="$value" ;;
                EXIT_SIGNAL) exit_signal="$value" ;;
                RECOMMENDATION) recommendation="$value" ;;
            esac
        done <<< "$ralph_output"

        log "INFO" "Ralph status: $status | Tasks: $tasks_completed | Tests: $tests_status"
        log "INFO" "Recommendation: $recommendation"

        # Record failing tests in VIGIL
        if [ "$tests_status" = "FAILING" ]; then
            vigil_record_error "TEST_FAILURE" "Loop $LOOP_COUNT: $recommendation"
        fi

        # Skinner decisions
        if [ "$status" = "COMPLETE" ]; then
            TOTAL_TASKS_COMPLETED=$((TOTAL_TASKS_COMPLETED + tasks_completed))
            run_gate_checks && skinner_commit "Loop $LOOP_COUNT complete: $recommendation"
            log "INFO" "All tasks complete. Stopping."
            break
        fi

        if [ "$tasks_completed" -gt 0 ] 2>/dev/null && [ "$tests_status" != "FAILING" ]; then
            TOTAL_TASKS_COMPLETED=$((TOTAL_TASKS_COMPLETED + tasks_completed))
            run_gate_checks && skinner_commit "Loop $LOOP_COUNT: $recommendation"
        elif [ "$tests_status" = "FAILING" ] && [ "$tasks_completed" -gt 0 ] 2>/dev/null; then
            log "WARN" "Tasks completed but tests failing — NOT committing. Ralph must fix tests next loop."
        fi

        # Circuit breaker check
        if ! check_circuit_breaker "$tasks_completed" "$tests_status" "$exit_signal" "$recommendation"; then
            log "CIRCUIT" "Circuit breaker OPEN — stopping Ralph"
            break
        fi
    done

    # Final report
    log_separator
    log "INFO" "SESSION REPORT"
    log "INFO" "  Project: $PROJECT_NAME"
    log "INFO" "  Workspace: ${WORKSPACE_NAME:-root}"
    log "INFO" "  Loops executed: $LOOP_COUNT"
    log "INFO" "  Tasks completed: $TOTAL_TASKS_COMPLETED"
    log "INFO" "  No-progress count: $NO_PROGRESS_COUNT"
    log "INFO" "  Same-error count: $SAME_ERROR_COUNT"
    log "INFO" "  Worktree: $WORKTREE_DIR"
    log "INFO" "  Branch: $WORKTREE_BRANCH"
    log "INFO" "  Log: $LOG_FILE"
    [ "$VIGIL_ENABLED" = "true" ] && log "INFO" "  VIGIL memory: $VIGIL_FILE"
    log_separator

    if [ "$TOTAL_TASKS_COMPLETED" -gt 0 ]; then
        local current_branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)
        log "INFO" "NEXT STEPS:"
        log "INFO" "  1. Review changes:  git log $WORKTREE_BRANCH --oneline"
        log "INFO" "  2. Diff vs base:    git diff $current_branch..$WORKTREE_BRANCH"
        log "INFO" "  3. Merge if good:   git checkout $current_branch && git merge $WORKTREE_BRANCH"
        log "INFO" "  4. Cleanup:         git worktree remove $WORKTREE_DIR && git branch -D $WORKTREE_BRANCH"
    fi
}

main
