---
description: "Configurar um projeto no workspace/ do motor. Funciona com projetos novos E existentes. Usage: /setup-workspace <nome> [--type node|python|java|bash|android] [--desc 'descricao'] [--clone <git-url>]"
---

## User Input

```text
$ARGUMENTS
```

## Goal

Configurar um projeto dentro de `workspace/` do motor AI-Brain Engine v2.
Funciona em 3 cenarios:

1. **Projeto novo** — cria do zero com estrutura padrao
2. **Projeto existente** — ja esta em `workspace/<nome>/` (copiado ou clonado manualmente)
3. **Clone** — clona de uma URL git para `workspace/<nome>/`

**IMPORTANTE:** Arquivos do motor (.ralphrc, .ralph/, CLAUDE.md) ficam em `configs/<nome>/` no motor, NAO no repo do projeto. O projeto fica limpo — apenas codigo, specs e docs.

## Instructions

### 1. Parse Arguments

Extract from user input:
- `PROJECT_NAME` (required) — nome do projeto
- `PROJECT_TYPE` (optional, default: node) — tipo: node, python, java, android, bash
- `PROJECT_DESC` (optional) — descricao curta do projeto
- `CLONE_URL` (optional) — URL git para clonar

### 2. Detect Scenario

```
MOTOR_ROOT=$(pwd)
PROJECT_DIR="$MOTOR_ROOT/workspace/$PROJECT_NAME"
CONFIG_DIR="$MOTOR_ROOT/configs/$PROJECT_NAME"
```

**Scenario A — Clone:**
If `CLONE_URL` is provided:
```bash
mkdir -p workspace/
git clone "$CLONE_URL" "$PROJECT_DIR"
```

**Scenario B — Existing project:**
If `workspace/<PROJECT_NAME>/` already exists:
- Check if it has `.git/` — if yes, it's already a repo (good)
- Check if `configs/<PROJECT_NAME>/` exists — if yes, already configured, ask user if they want to reconfigure
- If no `.git/`, ask user: "Esse projeto nao tem repositorio git. Deseja inicializar um?"

**Scenario C — New project:**
If `workspace/<PROJECT_NAME>/` does NOT exist:
```bash
mkdir -p "$PROJECT_DIR"/{src,tests,docs,specs}
cd "$PROJECT_DIR"
git init
```

### 3. Detect Project Type (if not provided)

If `--type` was not specified and the project already exists, auto-detect:
- `package.json` exists → node
- `requirements.txt` or `pyproject.toml` or `setup.py` exists → python
- `pom.xml` or `build.gradle` or `build.gradle.kts` exists → java
- `build.gradle.kts` + `AndroidManifest.xml` exists → android
- Otherwise → ask user or default to node

### 4. Create Motor Config Files

These files live in `configs/<PROJECT_NAME>/` in the motor repo (NOT in the project).
**Only create if they don't exist** (don't overwrite user's work).

```bash
mkdir -p "$CONFIG_DIR/.ralph"
```

#### 4a. `.ralphrc` (project config for Ralph)

If `configs/<PROJECT_NAME>/.ralphrc` does NOT exist, create it:

```bash
# .ralphrc - Ralph project configuration
# Project: <PROJECT_NAME>

PROJECT_NAME="<PROJECT_NAME>"
PROJECT_TYPE="<PROJECT_TYPE>"
PROJECT_ROOT="."

CLAUDE_CODE_CMD="claude"

MAX_CALLS_PER_HOUR=100
CLAUDE_TIMEOUT_MINUTES=15

ALLOWED_TOOLS="Write,Read,Edit,Bash(git add *),Bash(git commit *),Bash(git diff *),Bash(git log *),Bash(git status),Bash(git status *),Bash(mkdir *),Bash(ls *)"

SESSION_CONTINUITY=true
SESSION_EXPIRY_HOURS=24

TASK_SOURCES="local"
GITHUB_TASK_LABEL="ralph-task"

CB_NO_PROGRESS_THRESHOLD=3
CB_SAME_ERROR_THRESHOLD=5
CB_OUTPUT_DECLINE_THRESHOLD=70
```

Adjust `ALLOWED_TOOLS` based on PROJECT_TYPE:
- **node**: add `Bash(npm *),Bash(npx *)`
- **python**: add `Bash(python *),Bash(pip *),Bash(pytest *),Bash(uvx *)`
- **java**: add `Bash(mvn *),Bash(gradle *)`
- **android**: add `Bash(./gradlew *),Bash(gradle *)`
- **bash**: keep minimal

#### 4b. `.ralph/` directory

If `configs/<PROJECT_NAME>/.ralph/` is empty, create:

Write `configs/<PROJECT_NAME>/.ralph/fix_plan.md`:
```markdown
# Fix Plan — <PROJECT_NAME>

## Tasks

- [ ] Task 1: (adicionar tasks aqui)
```

Write `configs/<PROJECT_NAME>/.ralph/AGENT.md`:
```markdown
# Ralph Agent — <PROJECT_NAME>

## Project
- **Type:** <PROJECT_TYPE>
- **Source:** <detect source root>

## Build & Test
<commands based on PROJECT_TYPE — detect from package.json, Makefile, build.gradle etc.>

## Key Principles
- ONE task per Ralph loop
- No Spec, No Code — consultar specs/ antes de implementar
- Do NOT commit — Skinner handles commits

## Specs (Source of Truth)
- `specs/` — Especificacoes

## Status Reporting
At the end of your response, ALWAYS include:
---RALPH_STATUS---
STATUS: IN_PROGRESS | COMPLETE | BLOCKED
TASKS_COMPLETED_THIS_LOOP: <number>
FILES_MODIFIED: <number>
TESTS_STATUS: PASSING | FAILING | NOT_RUN
WORK_TYPE: IMPLEMENTATION | TESTING | DOCUMENTATION | REFACTORING
EXIT_SIGNAL: false | true
RECOMMENDATION: <one line>
---END_RALPH_STATUS---
```

If AGENT.md can be auto-detected (e.g., read package.json scripts), populate it automatically.

#### 4c. `CLAUDE.md` (project governance)

If `configs/<PROJECT_NAME>/CLAUDE.md` does NOT exist, create it:

```markdown
# <PROJECT_NAME>
## Governance

This project runs under **AI-Brain Engine v2** motor.
Config: `configs/<PROJECT_NAME>/` (no motor)

## Tech Stack
<based on PROJECT_TYPE and detected dependencies>

## Key Commands
- Run Ralph: `./ralph-loop.sh <PROJECT_NAME>`
- Validate: `./validate.sh <PROJECT_NAME>`
- Skinner Status: `/skinner-status <PROJECT_NAME>`

## Directory Structure
<detect and document existing structure>

## Language
- Docs in PT-BR
- Code in English
```

### 5. Project-side setup (minimal)

Only touch the project for things that MUST be in the project repo:

#### 5a. `.gitignore` — add `.worktrees/`

Skinner creates worktrees inside the project. Make sure they're ignored:
```bash
# Only if .worktrees/ is not already in .gitignore
grep -q ".worktrees/" "$PROJECT_DIR/.gitignore" 2>/dev/null || echo ".worktrees/" >> "$PROJECT_DIR/.gitignore"
```

If `.gitignore` does NOT exist, create a standard one for the project type.

#### 5b. Create `specs/` directory

Only create if it doesn't exist (source of truth for the motor):
```bash
mkdir -p "$PROJECT_DIR/specs"
```

For new projects only, also create: `src/`, `tests/`, `docs/`

### 6. Show Summary

Adapt output based on scenario:

**For clone / existing project:**
```
Projeto configurado para o motor!

  Projeto: <PROJECT_NAME>
  Tipo: <PROJECT_TYPE> (detectado automaticamente)
  Workspace: workspace/<PROJECT_NAME>/
  Config: configs/<PROJECT_NAME>/
  Git: repositorio existente mantido

Configs criados no motor:
  configs/<PROJECT_NAME>/.ralphrc    — Config Ralph
  configs/<PROJECT_NAME>/.ralph/     — Templates Ralph (AGENT, fix_plan)
  configs/<PROJECT_NAME>/CLAUDE.md   — Governanca do projeto

Proximos passos:
  1. Revise configs/<PROJECT_NAME>/.ralphrc e ajuste ALLOWED_TOOLS se necessario
  2. Revise configs/<PROJECT_NAME>/.ralph/AGENT.md e ajuste comandos de build/test
  3. Adicione tasks em configs/<PROJECT_NAME>/.ralph/fix_plan.md
  4. Rode Ralph: ./ralph-loop.sh <PROJECT_NAME>
```

**For new project:**
```
Workspace criado com sucesso!

  Projeto: <PROJECT_NAME>
  Tipo: <PROJECT_TYPE>
  Workspace: workspace/<PROJECT_NAME>/
  Config: configs/<PROJECT_NAME>/
  Git: repositorio independente (novo)

Proximos passos:
  1. Adicione specs em workspace/<PROJECT_NAME>/specs/
  2. Adicione tasks em configs/<PROJECT_NAME>/.ralph/fix_plan.md
  3. Rode Ralph: ./ralph-loop.sh <PROJECT_NAME>
```

## Language

- **ALL output MUST be in Brazilian Portuguese (PT-BR)**
