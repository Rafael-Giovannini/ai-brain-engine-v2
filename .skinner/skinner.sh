#!/bin/bash
###############################################################################
# SKINNER ENFORCEMENT ENGINE v2
# Controle de qualidade para o loop autonomo do Ralph.
#
# ARQUITETURA NESTED-REPOS:
#   - MOTOR_ROOT: raiz do motor (engine.yaml, .skinner/, .ralph/ templates)
#   - PROJECT_DIR: raiz do projeto (repo git independente em workspace/)
#   - Skinner le configs do MOTOR, mas opera git dentro do PROJETO
#   - Worktrees sao criados no repo do PROJETO
#   - Logs e VIGIL ficam no MOTOR (.skinner/logs/, .skinner/memory/)
#
# Evolucao do v1 com:
#   - Leitura de engine.yaml para flags de camadas
#   - Integracao com VIGIL (memoria comportamental)
#   - Suporte a Langfuse tracing (quando habilitado)
#   - Testes de arquitetura como gate (quando habilitado)
#   - Mutation testing como gate (quando habilitado)
#
# Responsabilidades:
#   1. Criar worktree isolado para Ralph trabalhar (no repo do projeto)
#   2. Commit atomico apos cada loop bem-sucedido
#   3. Deteccao de erro circular / alucinacao → auto-revert
#   4. Circuit breaker → parar Ralph se nao houver progresso
#   5. Log de auditoria de todas as acoes
#   6. VIGIL: registrar erros e adaptar prompts (v2)
#
# Uso:
#   ./skinner.sh --workspace ghostfit [--dry-run] [--max-loops N] [--prompt "task"]
#
# Environment (set by ralph-loop.sh):
#   MOTOR_ROOT  — path to the engine root
#   PROJECT_DIR — path to the project root (workspace/<name>)
###############################################################################

set -euo pipefail

# ─── Config ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# MOTOR_ROOT: where engine.yaml, .skinner/, .ralph/ templates live
MOTOR_ROOT="${MOTOR_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

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

# PROJECT_DIR: where the actual code lives (independent git repo)
PROJECT_DIR="${PROJECT_DIR:-$MOTOR_ROOT/workspace/$WORKSPACE_NAME}"

# ─── Engine Config ─────────────────────────────────────────────────────────
# Read engine.yaml from MOTOR (not project)
ENGINE_YAML="$MOTOR_ROOT/engine.yaml"

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

# Layer flags (from motor's engine.yaml)
is_layer_enabled() {
    local layer="$1"
    if [ -f "$ENGINE_YAML" ]; then
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
# Config resolution order: motor configs/<workspace>/ → project dir → motor .ralph/ (generic)
CONFIG_DIR="$MOTOR_ROOT/configs/$WORKSPACE_NAME"

# .ralphrc: motor configs/ first, then project
if [ -f "$CONFIG_DIR/.ralphrc" ]; then
    RALPHRC="$CONFIG_DIR/.ralphrc"
elif [ -f "$PROJECT_DIR/.ralphrc" ]; then
    RALPHRC="$PROJECT_DIR/.ralphrc"
else
    echo "ERROR: No .ralphrc found for workspace '$WORKSPACE_NAME'"
    echo "Expected at: $CONFIG_DIR/.ralphrc or $PROJECT_DIR/.ralphrc"
    exit 1
fi

# .ralph/ templates: motor configs/ first, then project, then motor generic
if [ -d "$CONFIG_DIR/.ralph" ]; then
    RALPH_DIR="$CONFIG_DIR/.ralph"
elif [ -d "$PROJECT_DIR/.ralph" ]; then
    RALPH_DIR="$PROJECT_DIR/.ralph"
else
    RALPH_DIR="$MOTOR_ROOT/.ralph"
fi

# CLAUDE.md for the project: motor configs/ first, then project
if [ -f "$CONFIG_DIR/CLAUDE.md" ]; then
    PROJECT_CLAUDE_MD="$CONFIG_DIR/CLAUDE.md"
elif [ -f "$PROJECT_DIR/CLAUDE.md" ]; then
    PROJECT_CLAUDE_MD="$PROJECT_DIR/CLAUDE.md"
else
    PROJECT_CLAUDE_MD=""
fi

# ─── State tracking ─────────────────────────────────────────────────────────
WORKTREE_DIR=""
WORKTREE_BRANCH=""
# Logs and memory stay in the MOTOR (shared across projects)
LOG_DIR="$MOTOR_ROOT/.skinner/logs/$WORKSPACE_NAME"
LOG_FILE="$LOG_DIR/session-$(date +%Y%m%d-%H%M%S).log"
MEMORY_DIR="$MOTOR_ROOT/.skinner/memory"
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

# ─── Load config ─────────────────────────────────────────────────────────────
source "$RALPHRC"
log "INFO" "Config loaded from: $RALPHRC"
log "INFO" "Ralph templates from: $RALPH_DIR"

# Defaults (overridden by .ralphrc or engine.yaml)
PROJECT_NAME="${PROJECT_NAME:-$WORKSPACE_NAME}"
PROJECT_ROOT="${PROJECT_ROOT:-.}"
CLAUDE_CODE_CMD="${CLAUDE_CODE_CMD:-claude}"
CB_NO_PROGRESS_THRESHOLD="${CB_NO_PROGRESS_THRESHOLD:-3}"
CB_SAME_ERROR_THRESHOLD="${CB_SAME_ERROR_THRESHOLD:-5}"
MAX_LOOPS="${MAX_LOOPS_ARG:-${MAX_LOOPS:-20}}"

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
    if [ "$VIGIL_ENABLED" = "true" ] && [ -f "$VIGIL_FILE" ]; then
        local max_errors
        max_errors=$(engine_get "max_context_errors" "5")
        local workspace_filter="${WORKSPACE_NAME:-root}"

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

# ─── Template Resolution ──────────────────────────────────────────────────
# Resolves {{PLACEHOLDER}} values in generic .ralph/ templates using data from
# .ralphrc, AGENT.md, and CLAUDE.md. This ensures Ralph gets a proper system prompt
# even when project-specific templates are not provided.

extract_section() {
    # Extract content between ## $section_name and the next ## heading
    local file="$1"
    local section="$2"
    if [ -f "$file" ]; then
        sed -n "/^## ${section}/,/^## /{ /^## ${section}/d; /^## /d; p; }" "$file" | sed '/^$/{ N; /^\n$/d; }' | sed -e 's/^[[:space:]]*//' -e '/^$/d'
    fi
}

# Build a substitution map from project context.
# Sets global associative-like vars: TPL_* for each known placeholder.
build_template_vars() {
    local wt_ralph="$WORKTREE_DIR/.ralph"
    local agent_md="$wt_ralph/AGENT.md"
    local claude_md="$WORKTREE_DIR/CLAUDE.md"

    # Simple vars (from .ralphrc)
    TPL_PROJECT_NAME="$PROJECT_NAME"
    TPL_PROJECT_TYPE="${PROJECT_TYPE:-unknown}"
    TPL_PROJECT_ROOT="${PROJECT_ROOT:-.}"
    TPL_BRANCH="$WORKTREE_BRANCH"

    # Multi-line vars extracted from AGENT.md
    TPL_TECH_STACK="" TPL_ARCHITECTURE="" TPL_SPECS_AND_DOCS=""
    TPL_TEST_COMMANDS="" TPL_PROJECT_OVERVIEW="" TPL_VIGIL_CONTEXT=""
    TPL_PREREQUISITES="" TPL_BUILD_COMMANDS="" TPL_RUN_COMMANDS=""
    TPL_PROJECT_STRUCTURE="" TPL_NOTES=""
    TPL_SPEC_PATH="" TPL_PLAN_PATH="" TPL_STORY_1_NAME=""

    if [ -f "$agent_md" ]; then
        TPL_TECH_STACK=$(extract_section "$agent_md" "Tech Stack")
        TPL_ARCHITECTURE=$(extract_section "$agent_md" "Architecture")
        TPL_SPECS_AND_DOCS=$(extract_section "$agent_md" "Specs (Source of Truth)")
        TPL_TEST_COMMANDS=$(extract_section "$agent_md" "Build & Test")
        TPL_PREREQUISITES=$(extract_section "$agent_md" "Prerequisites")
        TPL_BUILD_COMMANDS=$(extract_section "$agent_md" "Build Instructions")
        TPL_RUN_COMMANDS=$(extract_section "$agent_md" "Install & Run")
        TPL_PROJECT_STRUCTURE=$(extract_section "$agent_md" "Project Structure" || extract_section "$agent_md" "Architecture")
        TPL_NOTES=$(extract_section "$agent_md" "Notes")
    fi

    # Fallback to CLAUDE.md if AGENT.md sections are empty or have unresolved placeholders
    if [ -f "$claude_md" ]; then
        if [ -z "$TPL_TECH_STACK" ] || echo "$TPL_TECH_STACK" | grep -q '{{'; then
            TPL_TECH_STACK=$(extract_section "$claude_md" "Tech Stack")
        fi
        if [ -z "$TPL_PROJECT_OVERVIEW" ]; then
            TPL_PROJECT_OVERVIEW=$(extract_section "$claude_md" "Governance" | head -3)
        fi
        if [ -z "$TPL_PROJECT_STRUCTURE" ] || echo "$TPL_PROJECT_STRUCTURE" | grep -q '{{'; then
            TPL_PROJECT_STRUCTURE=$(extract_section "$claude_md" "Directory Structure")
        fi
    fi

    # Detect spec/plan paths from specs/ directory
    local specs_dir="$WORKTREE_DIR/specs"
    if [ -d "$specs_dir" ]; then
        local feature_dir
        feature_dir=$(ls -d "$specs_dir"/[0-9]*/ 2>/dev/null | sort -V | tail -1)
        if [ -n "$feature_dir" ]; then
            feature_dir="${feature_dir%/}"
            [ -f "$feature_dir/spec.md" ] && TPL_SPEC_PATH="${feature_dir#$WORKTREE_DIR/}/spec.md"
            [ -f "$feature_dir/plan.md" ] && TPL_PLAN_PATH="${feature_dir#$WORKTREE_DIR/}/plan.md"
            # Extract first story name from spec.md
            if [ -f "$feature_dir/spec.md" ]; then
                TPL_STORY_1_NAME=$(grep -m1 "User Story 1" "$feature_dir/spec.md" | sed 's/.*User Story 1[^—]*— *//' | sed 's/ *(.*//' || echo "Core Feature")
            fi
        elif [ -f "$specs_dir/spec.md" ]; then
            TPL_SPEC_PATH="specs/spec.md"
            [ -f "$specs_dir/plan.md" ] && TPL_PLAN_PATH="specs/plan.md"
        fi
    fi

    # Final fallbacks
    : "${TPL_TECH_STACK:=See AGENT.md for tech stack details}"
    : "${TPL_ARCHITECTURE:=See AGENT.md for architecture details}"
    : "${TPL_SPECS_AND_DOCS:=Check specs/ directory for specifications}"
    : "${TPL_TEST_COMMANDS:=See AGENT.md for test commands}"
    : "${TPL_PROJECT_OVERVIEW:=See CLAUDE.md and AGENT.md for project details}"
    : "${TPL_VIGIL_CONTEXT:=(Injected at runtime by Skinner)}"
    : "${TPL_PREREQUISITES:=See AGENT.md}"
    : "${TPL_BUILD_COMMANDS:=See AGENT.md}"
    : "${TPL_RUN_COMMANDS:=See AGENT.md}"
    : "${TPL_PROJECT_STRUCTURE:=See AGENT.md}"
    : "${TPL_NOTES:=}"
    : "${TPL_SPEC_PATH:=specs/spec.md}"
    : "${TPL_PLAN_PATH:=specs/plan.md}"
    : "${TPL_STORY_1_NAME:=Core Feature}"
}

# Resolve all {{PLACEHOLDER}} values in a single file.
# Usage: resolve_template_file <filepath>
# Skips files that have no {{...}} placeholders.
resolve_template_file() {
    local filepath="$1"

    [ -f "$filepath" ] || return 0

    # Skip if no placeholders
    grep -q '{{' "$filepath" || return 0

    log "INFO" "Resolving template: $(basename "$filepath")"

    local tmpfile
    tmpfile=$(mktemp)
    cp "$filepath" "$tmpfile"

    # Simple single-line substitutions via sed
    sed -i "s|{{PROJECT_NAME}}|${TPL_PROJECT_NAME}|g" "$tmpfile"
    sed -i "s|{{PROJECT_TYPE}}|${TPL_PROJECT_TYPE}|g" "$tmpfile"
    sed -i "s|{{PROJECT_ROOT}}|${TPL_PROJECT_ROOT}|g" "$tmpfile"
    sed -i "s|{{BRANCH}}|${TPL_BRANCH}|g" "$tmpfile"
    sed -i "s|{{SPEC_PATH}}|${TPL_SPEC_PATH}|g" "$tmpfile"
    sed -i "s|{{PLAN_PATH}}|${TPL_PLAN_PATH}|g" "$tmpfile"
    sed -i "s|{{STORY_1_NAME}}|${TPL_STORY_1_NAME}|g" "$tmpfile"

    # Multi-line substitutions using awk (for placeholders that are alone on a line)
    local multi_placeholders="PROJECT_OVERVIEW TECH_STACK ARCHITECTURE SPECS_AND_DOCS TEST_COMMANDS VIGIL_CONTEXT PREREQUISITES BUILD_COMMANDS RUN_COMMANDS PROJECT_STRUCTURE NOTES"

    for placeholder in $multi_placeholders; do
        # Skip if placeholder not present
        grep -q "{{${placeholder}}}" "$tmpfile" || continue

        local value=""
        eval "value=\"\${TPL_${placeholder}}\""

        local val_file
        val_file=$(mktemp)
        echo "$value" > "$val_file"

        awk -v placeholder="{{${placeholder}}}" -v valfile="$val_file" '
        {
            if (index($0, placeholder)) {
                while ((getline line < valfile) > 0) print line
                close(valfile)
            } else {
                print
            }
        }' "$tmpfile" > "${tmpfile}.new"
        mv "${tmpfile}.new" "$tmpfile"
        rm -f "$val_file"
    done

    cp "$tmpfile" "$filepath"
    rm -f "$tmpfile"
}

# Resolve all templates in the worktree's .ralph/ directory.
# For files that already exist (project-specific), skip if no placeholders.
# For PROMPT.md, copy from generic template if missing, then resolve.
resolve_prompt_template() {
    local wt_ralph="$WORKTREE_DIR/.ralph"

    # Build the substitution variables once
    build_template_vars

    # PROMPT.md: copy from generic if missing
    if [ ! -f "$wt_ralph/PROMPT.md" ] && [ -f "$MOTOR_ROOT/.ralph/PROMPT.md" ]; then
        cp "$MOTOR_ROOT/.ralph/PROMPT.md" "$wt_ralph/PROMPT.md"
        log "INFO" "Copied generic PROMPT.md to worktree"
    fi

    # Resolve all .md files in .ralph/ that contain {{placeholders}}
    for md_file in "$wt_ralph"/*.md; do
        [ -f "$md_file" ] || continue
        resolve_template_file "$md_file"
    done

    log "INFO" "Template resolution complete"
}

# ─── Worktree Management ────────────────────────────────────────────────────
# Worktrees are created in the PROJECT's git repo (not the motor)
create_worktree() {
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local wt_name="${WORKSPACE_NAME:-ralph}"
    WORKTREE_BRANCH="ralph/$wt_name-$timestamp"
    # Worktree dir lives alongside the project (not inside motor)
    WORKTREE_DIR="$PROJECT_DIR/.worktrees/$wt_name-$timestamp"

    log "INFO" "Creating worktree in PROJECT repo: $PROJECT_DIR"
    log "INFO" "Branch: $WORKTREE_BRANCH"
    log "INFO" "Location: $WORKTREE_DIR"

    mkdir -p "$(dirname "$WORKTREE_DIR")"
    git -C "$PROJECT_DIR" worktree add -b "$WORKTREE_BRANCH" "$WORKTREE_DIR" HEAD

    # Copy resolved config into worktree (from motor configs/ or project)
    cp -r "$RALPH_DIR" "$WORKTREE_DIR/.ralph"
    log "INFO" "Copied .ralph/ from: $RALPH_DIR"

    cp "$RALPHRC" "$WORKTREE_DIR/.ralphrc"
    log "INFO" "Copied .ralphrc from: $RALPHRC"

    if [ -n "$PROJECT_CLAUDE_MD" ]; then
        cp "$PROJECT_CLAUDE_MD" "$WORKTREE_DIR/CLAUDE.md"
        log "INFO" "Copied CLAUDE.md from: $PROJECT_CLAUDE_MD"
    fi

    # Resolve PROMPT.md template if not present in project config
    resolve_prompt_template

    log "INFO" "Worktree created successfully"
    LAST_GOOD_COMMIT=$(git -C "$WORKTREE_DIR" rev-parse HEAD)
    log "INFO" "Base commit: $LAST_GOOD_COMMIT"
}

cleanup_worktree() {
    if [ -n "$WORKTREE_DIR" ] && [ -d "$WORKTREE_DIR" ]; then
        local changes=$(git -C "$WORKTREE_DIR" diff --stat HEAD 2>/dev/null || true)
        local current_branch=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD)
        if [ -n "$changes" ]; then
            log "WARN" "Uncommitted changes in worktree — leaving for review"
            log "INFO" "Worktree preserved at: $WORKTREE_DIR"
            log "INFO" "Branch: $WORKTREE_BRANCH"
            log "INFO" "To merge: cd $PROJECT_DIR && git merge $WORKTREE_BRANCH"
            log "INFO" "To remove: git worktree remove $WORKTREE_DIR"
        else
            log "INFO" "No uncommitted changes. Review commits before merging."
            log "INFO" "Worktree at: $WORKTREE_DIR"
            log "INFO" "To merge: cd $PROJECT_DIR && git checkout $current_branch && git merge $WORKTREE_BRANCH"
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

    # Stage all changes
    git add -A

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

    if [ "$exit_signal" = "true" ]; then
        log "CIRCUIT" "Ralph requested exit: $recommendation"
        return 1
    fi

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

    if [ "$ARCHUNIT_ENABLED" = "true" ]; then
        log "GATE" "Running architecture tests..."
        log "GATE" "ArchUnit gate: SKIPPED (not yet configured for this project)"
    fi

    if [ "$MUTAHUNTER_ENABLED" = "true" ]; then
        log "GATE" "Running mutation testing..."
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

    # Allowed tools from .ralphrc (strip trailing comma if present)
    if [ -n "${ALLOWED_TOOLS:-}" ]; then
        ALLOWED_TOOLS="${ALLOWED_TOOLS%,}"
        cmd_args+=("--allowedTools" "$ALLOWED_TOOLS")
    fi

    cmd_args+=("-p" "$prompt")

    log "INFO" "Running: $CLAUDE_CODE_CMD --print -p '<prompt>' (${#cmd_args[@]} args)"
    log "INFO" "Working directory: $WORKTREE_DIR"

    local output
    output=$(unset CLAUDECODE; "$CLAUDE_CODE_CMD" "${cmd_args[@]}" 2>&1) || true

    echo "$output" >> "$LOG_FILE"

    parse_ralph_status "$output"
}

# ─── Main Loop ───────────────────────────────────────────────────────────────
main() {
    log_separator
    log "INFO" "SKINNER ENFORCEMENT ENGINE v2 — $PROJECT_NAME"
    log "INFO" "Motor: $MOTOR_ROOT"
    log "INFO" "Project: $PROJECT_DIR"
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
    log "INFO" "  Motor: $MOTOR_ROOT"
    log "INFO" "  Project dir: $PROJECT_DIR"
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
        local current_branch=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD)
        log "INFO" "NEXT STEPS:"
        log "INFO" "  1. Review changes:  cd $PROJECT_DIR && git log $WORKTREE_BRANCH --oneline"
        log "INFO" "  2. Diff vs base:    git diff $current_branch..$WORKTREE_BRANCH"
        log "INFO" "  3. Merge if good:   git checkout $current_branch && git merge $WORKTREE_BRANCH"
        log "INFO" "  4. Cleanup:         git worktree remove $WORKTREE_DIR && git branch -D $WORKTREE_BRANCH"
    fi
}

main
