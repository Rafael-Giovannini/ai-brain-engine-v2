#!/bin/bash
###############################################################################
# VALIDATE — Spec-vs-Code Validation Engine
#
# Valida consistência entre documentação e código, mais qualidade de código.
#
# Uso:
#   ./validate.sh ghostfit                             # Auto-detect feature
#   ./validate.sh ghostfit --feature 001-ghostfit-mvp  # Feature específica
#   ./validate.sh motor-financeiro                     # Outro workspace
#   ./validate.sh ghostfit --dry-run                   # Mostra prompt sem rodar
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_CODE_CMD="${CLAUDE_CODE_CMD:-claude}"

# ─── Parse args ──────────────────────────────────────────────────────────────
WORKSPACE_NAME=""
FEATURE_NAME=""
BRANCH_NAME=""
DRY_RUN=false
WORKTREE_PATH=""

# First arg must be workspace name
if [ -z "${1:-}" ] || [[ "${1:-}" == --* ]]; then
    echo "ERROR: Workspace name required as first argument."
    echo ""
    echo "Usage: ./validate.sh <workspace-name> [options]"
    echo ""
    echo "Options:"
    echo "  --feature NAME   Validate specific feature (default: auto-detect)"
    echo "  --branch NAME    Checkout branch before validating (e.g. ralph/ghostfit-XXXXX)"
    echo "  --dry-run        Print prompt without running Claude"
    echo ""
    echo "Available workspaces:"
    for dir in "$SCRIPT_DIR"/workspace/*/; do
        if [ -d "$dir/specs" ]; then
            echo "  - $(basename "$dir")"
        fi
    done
    exit 1
fi

WORKSPACE_NAME="$1"
shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --feature) FEATURE_NAME="$2"; shift 2 ;;
        --branch) BRANCH_NAME="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

# ─── Resolve workspace ──────────────────────────────────────────────────────
# Must resolve workspace BEFORE branch checkout, since branches live in the PROJECT repo
WORKSPACE_DIR="$SCRIPT_DIR/workspace/$WORKSPACE_NAME"

if [ ! -d "$WORKSPACE_DIR" ]; then
    echo "ERROR: Workspace not found: $WORKSPACE_DIR"
    exit 1
fi

# ─── Branch checkout (if requested) ─────────────────────────────────────────
# Branches are in the PROJECT's git repo (not the motor)
ORIGINAL_BRANCH=""
if [ -n "$BRANCH_NAME" ]; then
    ORIGINAL_BRANCH=$(git -C "$WORKSPACE_DIR" rev-parse --abbrev-ref HEAD)
    echo "Switching to branch: $BRANCH_NAME"
    echo "  (will return to $ORIGINAL_BRANCH after validation)"
    echo ""

    # Check if it's a worktree branch — try to find the worktree path
    WORKTREE_PATH=$(git -C "$WORKSPACE_DIR" worktree list --porcelain | grep -B2 "branch refs/heads/$BRANCH_NAME" | grep "^worktree " | sed 's/^worktree //' || true)

    if [ -n "$WORKTREE_PATH" ] && [ -d "$WORKTREE_PATH" ]; then
        echo "Found worktree at: $WORKTREE_PATH"
        echo "Validating directly from worktree (no checkout needed)."
        echo ""
        # Override WORKSPACE_DIR to point to the worktree
        WORKSPACE_DIR="$WORKTREE_PATH"
    else
        # No worktree, do a regular checkout in the project repo
        git -C "$WORKSPACE_DIR" stash --quiet 2>/dev/null || true
        git -C "$WORKSPACE_DIR" checkout "$BRANCH_NAME" --quiet 2>/dev/null || {
            echo "ERROR: Could not checkout branch: $BRANCH_NAME"
            git -C "$WORKSPACE_DIR" stash pop --quiet 2>/dev/null || true
            exit 1
        }
    fi
fi

# Cleanup: return to original branch on exit (in the PROJECT repo)
cleanup_branch() {
    if [ -n "$ORIGINAL_BRANCH" ] && [ -z "$WORKTREE_PATH" ]; then
        echo ""
        echo "Returning to branch: $ORIGINAL_BRANCH"
        git -C "$WORKSPACE_DIR" checkout "$ORIGINAL_BRANCH" --quiet 2>/dev/null || true
        git -C "$WORKSPACE_DIR" stash pop --quiet 2>/dev/null || true
    fi
}
trap cleanup_branch EXIT

SPECS_DIR="$WORKSPACE_DIR/specs"

if [ ! -d "$SPECS_DIR" ]; then
    echo "ERROR: No specs/ directory found in workspace/$WORKSPACE_NAME/"
    exit 1
fi

# ─── Detect feature layout ──────────────────────────────────────────────────
FEATURE_DIR=""

if [ -n "$FEATURE_NAME" ]; then
    # Explicit feature given
    FEATURE_DIR="$SPECS_DIR/$FEATURE_NAME"
elif [ -f "$SPECS_DIR/spec.md" ]; then
    # Flat layout (motor-financeiro style)
    FEATURE_DIR="$SPECS_DIR"
    FEATURE_NAME="$WORKSPACE_NAME"
else
    # Nested layout: find latest feature dir (highest numbered)
    FEATURE_DIR=$(ls -d "$SPECS_DIR"/[0-9]*/ 2>/dev/null | sort -V | tail -1)
    if [ -n "$FEATURE_DIR" ]; then
        FEATURE_DIR="${FEATURE_DIR%/}"  # Remove trailing slash
        FEATURE_NAME=$(basename "$FEATURE_DIR")
    fi
fi

if [ -z "$FEATURE_DIR" ] || [ ! -f "$FEATURE_DIR/spec.md" ]; then
    echo "ERROR: No spec.md found."
    echo "  Checked: $SPECS_DIR/spec.md"
    echo "  Checked: $SPECS_DIR/<NNN-feature>/spec.md"
    echo ""
    echo "Run /speckit.specify first to create a spec."
    exit 1
fi

echo "╔══════════════════════════════════════════════════════╗"
echo "║           VALIDATION ENGINE                         ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  Workspace: $WORKSPACE_NAME"
echo "║  Feature:   $FEATURE_NAME"
echo "║  Spec dir:  $FEATURE_DIR"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ─── Discover source & test directories ──────────────────────────────────────
SRC_DIR=""
for candidate in \
    "$WORKSPACE_DIR/android/app/src/main/java" \
    "$WORKSPACE_DIR/android/app/src/main/kotlin" \
    "$WORKSPACE_DIR/src" \
    "$WORKSPACE_DIR/lib" \
    "$WORKSPACE_DIR/app"; do
    if [ -d "$candidate" ]; then
        SRC_DIR="$candidate"
        break
    fi
done

TEST_DIRS=""
for candidate in \
    "$WORKSPACE_DIR/android/app/src/test" \
    "$WORKSPACE_DIR/android/app/src/androidTest" \
    "$WORKSPACE_DIR/tests" \
    "$WORKSPACE_DIR/test"; do
    if [ -d "$candidate" ]; then
        TEST_DIRS="$TEST_DIRS $candidate"
    fi
done

# ─── Discover spec files ────────────────────────────────────────────────────
SPEC_FILE="$FEATURE_DIR/spec.md"
PLAN_FILE="$FEATURE_DIR/plan.md"
DATA_MODEL_FILE="$FEATURE_DIR/data-model.md"
API_CONTRACT_FILE=$(ls "$FEATURE_DIR"/contracts/api*.md 2>/dev/null | head -1)

# ─── Discover BMAD docs ──────────────────────────────────────────────────────
DOCS_DIR="$WORKSPACE_DIR/docs"
BMAD_DOCS=""
if [ -d "$DOCS_DIR" ]; then
    for doc in "$DOCS_DIR"/*.md; do
        [ -f "$doc" ] && BMAD_DOCS="$BMAD_DOCS $doc"
    done
fi

# ─── Discover Ralph config ───────────────────────────────────────────────────
# Resolution order: motor configs/<workspace>/ → project workspace/<workspace>/
MOTOR_CONFIG_DIR="$SCRIPT_DIR/configs/$WORKSPACE_NAME"

if [ -f "$MOTOR_CONFIG_DIR/.ralphrc" ]; then
    RALPH_RC="$MOTOR_CONFIG_DIR/.ralphrc"
elif [ -f "$WORKSPACE_DIR/.ralphrc" ]; then
    RALPH_RC="$WORKSPACE_DIR/.ralphrc"
else
    RALPH_RC=""
fi

if [ -d "$MOTOR_CONFIG_DIR/.ralph" ]; then
    RALPH_CONFIG_SRC="$MOTOR_CONFIG_DIR/.ralph"
elif [ -d "$WORKSPACE_DIR/.ralph" ]; then
    RALPH_CONFIG_SRC="$WORKSPACE_DIR/.ralph"
else
    RALPH_CONFIG_SRC=""
fi

RALPH_PROMPT="${RALPH_CONFIG_SRC:+$RALPH_CONFIG_SRC/PROMPT.md}"
RALPH_AGENT="${RALPH_CONFIG_SRC:+$RALPH_CONFIG_SRC/AGENT.md}"
RALPH_FIXPLAN="${RALPH_CONFIG_SRC:+$RALPH_CONFIG_SRC/fix_plan.md}"

echo "Spec files found:"
echo "  spec.md:         $([ -f "$SPEC_FILE" ] && echo "YES" || echo "MISSING")"
echo "  plan.md:         $([ -f "$PLAN_FILE" ] && echo "YES" || echo "MISSING")"
echo "  data-model.md:   $([ -f "$DATA_MODEL_FILE" ] && echo "YES" || echo "MISSING")"
echo "  api-contracts:   $([ -n "$API_CONTRACT_FILE" ] && echo "YES" || echo "MISSING")"
echo ""
echo "BMAD docs:         $([ -n "$BMAD_DOCS" ] && echo "$(echo $BMAD_DOCS | wc -w) files" || echo "NOT FOUND")"
echo "Ralph config:      $([ -n "$RALPH_RC" ] && [ -f "$RALPH_RC" ] && echo "YES ($RALPH_RC)" || echo "MISSING")"
echo "Ralph .ralph/:     $([ -n "$RALPH_CONFIG_SRC" ] && [ -d "$RALPH_CONFIG_SRC" ] && echo "YES ($RALPH_CONFIG_SRC)" || echo "MISSING")"
echo ""
echo "Source code:       $([ -n "$SRC_DIR" ] && echo "$SRC_DIR" || echo "NOT FOUND")"
echo "Test directories:  $([ -n "$TEST_DIRS" ] && echo "$TEST_DIRS" || echo "NOT FOUND")"
echo ""

# ─── Build report path ──────────────────────────────────────────────────────
REPORT_PATH="$FEATURE_DIR/validation-report.md"

# ─── Build prompt ────────────────────────────────────────────────────────────
PROMPT="You are a validation engine for the AI-Brain monorepo.
IMPORTANT: All output (report, findings, recommendations, summaries) MUST be written in Brazilian Portuguese (PT-BR). Technical terms (file names, code identifiers, severity levels) may remain in English.

## Context
- Workspace: $WORKSPACE_NAME
- Feature: $FEATURE_NAME
- Report output: $REPORT_PATH

## Spec Files to Read
- spec.md: $SPEC_FILE
$([ -f "$PLAN_FILE" ] && echo "- plan.md: $PLAN_FILE" || echo "- plan.md: NOT AVAILABLE")
$([ -f "$DATA_MODEL_FILE" ] && echo "- data-model.md: $DATA_MODEL_FILE" || echo "- data-model.md: NOT AVAILABLE")
$([ -n "$API_CONTRACT_FILE" ] && echo "- api-contracts: $API_CONTRACT_FILE" || echo "- api-contracts: NOT AVAILABLE")

## BMAD Docs (in docs/)
$(if [ -n "$BMAD_DOCS" ]; then for doc in $BMAD_DOCS; do echo "- $doc"; done; else echo "- No BMAD docs found"; fi)

## Ralph Config
$([ -n "$RALPH_RC" ] && [ -f "$RALPH_RC" ] && echo "- .ralphrc: $RALPH_RC" || echo "- .ralphrc: NOT AVAILABLE")
$([ -n "$RALPH_PROMPT" ] && [ -f "$RALPH_PROMPT" ] && echo "- PROMPT.md: $RALPH_PROMPT" || echo "- PROMPT.md: NOT AVAILABLE")
$([ -n "$RALPH_AGENT" ] && [ -f "$RALPH_AGENT" ] && echo "- AGENT.md: $RALPH_AGENT" || echo "- AGENT.md: NOT AVAILABLE")
$([ -n "$RALPH_FIXPLAN" ] && [ -f "$RALPH_FIXPLAN" ] && echo "- fix_plan.md: $RALPH_FIXPLAN" || echo "- fix_plan.md: NOT AVAILABLE")

## Source Code
$([ -n "$SRC_DIR" ] && echo "- Source directory: $SRC_DIR" || echo "- NO SOURCE CODE FOUND — skip code validation passes, focus on doc consistency only")
$([ -n "$TEST_DIRS" ] && echo "- Test directories:$TEST_DIRS" || echo "- No test directories found")

## Instructions

Read ALL the files listed above. Then perform these 8 validation passes:

### Pass A: Doc Consistency
Compare spec.md vs plan.md vs data-model.md vs api-contracts.md:
- Entities in data-model match entities in spec
- Endpoints in contracts match plan architecture
- FRs referenced consistently across docs
- Enum values consistent between data-model and contracts
- Error messages in contracts match edge cases in spec

### Pass B: Entity Validation (Spec vs Code)
For each entity in data-model.md, search SRC_DIR for matching class/data class.
Check each field exists. Check enum values match.
Report: COMPLETE / PARTIAL / MISSING per entity.

### Pass C: API Contract Validation (Spec vs Code)
For each endpoint in api-contracts, search SRC_DIR for matching route handler.
Report: IMPLEMENTED / MISSING / PATH_MISMATCH per endpoint.

### Pass D: FR Traceability
For each FR-XXX in spec.md, search code and tests for references.
Report: TRACED / PARTIAL / UNTRACED per FR.

### Pass E: Acceptance Scenario vs Test Coverage
For each Given/When/Then scenario, search tests for matching methods.
Report: COVERED / UNCOVERED per scenario.

### Pass F: Code Quality Analysis
For each source file, check:

**Architecture & Clean Code:**
- Layer separation (domain must NOT import infrastructure/framework)
- Single Responsibility (flag files > 300 lines or classes > 10 public methods)
- Business logic must live in domain/use-case layer, not controllers/activities

**Security (OWASP):**
- No hardcoded secrets (API keys, passwords, tokens inline)
- Sensitive data encrypted properly
- Input validation at boundaries
- Parameterized queries only (no string concatenation in queries)

**Code Smells:**
- Duplicated code blocks
- Functions with > 5 parameters
- Deeply nested callbacks (> 3 levels)
- Magic numbers/strings (should be constants)
- TODO/FIXME/HACK without issue reference

**Tests:**
- Business logic has corresponding test files
- Descriptive test names (should_X_when_Y)

**Performance:**
- No blocking calls on main thread
- Async/coroutine for I/O
- No obvious memory leaks

### Pass G: BMAD Docs vs Specs
If BMAD docs exist, cross-validate:
- User Stories in spec match stories in sprint-plan
- Tech stack in architecture matches plan.md tech stack
- Screens/flows in UX design match UI screens in plan project structure
- NFRs and FRs in PRD match requirements in spec (count, descriptions)
- Priority ordering consistent between sprint-plan and spec

### Pass H: Ralph Config Validation
If Ralph config exists, validate:
- .ralphrc: PROJECT_NAME matches docs, PROJECT_TYPE matches tech stack, PROJECT_ROOT is correct, ALLOWED_TOOLS are safe and relevant
- PROMPT.md: Tech stack matches architecture/plan, branch name is correct, spec/doc paths listed actually exist
- AGENT.md: Build/test commands match project type, prerequisites match tech stack
- fix_plan.md: All stories match spec.md stories, priority order matches, no completed tasks referencing non-existent code

## Severity Rules
- CRITICAL: P1 entity missing; endpoint without implementation; hardcoded secret; SQL injection; PRD vs spec FR count mismatch
- HIGH: Entity with missing key fields; enum mismatch; business logic outside domain; significant duplication; architecture vs plan tech stack mismatch
- MEDIUM: FR without tests; scenario uncovered; code smells; Ralph config path errors; BMAD doc inconsistencies
- LOW: Naming inconsistencies; minor TODOs; extra code fields not in spec

## Output

Write the validation report to: $REPORT_PATH

Use this exact structure:

# Validation Report: $WORKSPACE_NAME / $FEATURE_NAME

**Generated**: $(date '+%Y-%m-%d %H:%M')

## Executive Summary
(table with metrics including: Spec Doc Consistency Issues, BMAD Docs Issues, Ralph Config Issues, Entities, Endpoints, FRs, Tests, Code Quality, Critical/High/Medium counts)

## 1. Spec Doc Consistency (Pass A)
(table: ID | Severity | Location | Finding | Recommendation)

## 2. Entity Coverage Matrix (Pass B)
(table: Entity | Code File | Status | Missing Fields)

## 3. API Contract Coverage (Pass C)
(table: Endpoint | Code File | Status | Notes)

## 4. FR Traceability (Pass D)
(table: FR | Description | In Code? | In Tests? | Status)

## 5. Acceptance Scenario Coverage (Pass E)
(table: Story | Scenario | Test Found? | Test File)

## 6. Code Quality (Pass F)
(table: File | Category | Severity | Finding | Recommendation)

## 7. BMAD Docs vs Specs (Pass G)
(table: ID | Severity | Docs File | Spec File | Finding | Recommendation)

## 8. Ralph Config (Pass H)
(table: ID | Severity | File | Finding | Recommendation)

## Next Actions
(grouped by severity: Critical, High, Medium)

Limit to 80 findings total. Be specific: cite file paths and field names."

# ─── Execute ─────────────────────────────────────────────────────────────────
if [ "$DRY_RUN" = true ]; then
    echo "═══════════════════════════════════════════════════════"
    echo "DRY RUN — Prompt that would be sent to Claude:"
    echo "═══════════════════════════════════════════════════════"
    echo "$PROMPT"
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "Report would be written to: $REPORT_PATH"
    exit 0
fi

echo "Running validation with Claude..."
echo "(this may take a few minutes)"
echo ""

"$CLAUDE_CODE_CMD" --print -p "$PROMPT" 2>&1 | tee -a /dev/stderr

echo ""
echo "═══════════════════════════════════════════════════════"
echo "Validation complete."
echo "Report: $REPORT_PATH"
echo "═══════════════════════════════════════════════════════"
