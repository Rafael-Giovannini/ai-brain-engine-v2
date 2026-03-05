---
description: "Configurar um projeto no workspace/ do motor. Funciona com projetos novos E existentes. Usage: /setup-workspace <nome> [--type node|python|java|bash] [--desc 'descricao'] [--clone <git-url>]"
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

Em todos os casos, adiciona os arquivos do motor (.ralphrc, .ralph/, CLAUDE.md) ao projeto.

## Instructions

### 1. Parse Arguments

Extract from user input:
- `PROJECT_NAME` (required) — nome do projeto
- `PROJECT_TYPE` (optional, default: node) — tipo: node, python, java, bash
- `PROJECT_DESC` (optional) — descricao curta do projeto
- `CLONE_URL` (optional) — URL git para clonar

### 2. Detect Scenario

```
MOTOR_ROOT=$(pwd)
PROJECT_DIR="$MOTOR_ROOT/workspace/$PROJECT_NAME"
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
- Check if it has `.ralphrc` — if yes, already configured, ask user if they want to reconfigure
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
- `pom.xml` or `build.gradle` exists → java
- Otherwise → ask user or default to node

### 4. Add Motor Integration Files

These files connect the project to the motor. **Only create if they don't exist** (don't overwrite user's work).

#### 4a. `.ralphrc` (project config for Ralph)

If `.ralphrc` does NOT exist, create it:

```bash
# .ralphrc - Ralph project configuration
# Project: <PROJECT_NAME>

PROJECT_NAME="<PROJECT_NAME>"
PROJECT_TYPE="<PROJECT_TYPE>"
PROJECT_ROOT="."

CLAUDE_CODE_CMD="claude"

MAX_CALLS_PER_HOUR=100
CLAUDE_TIMEOUT_MINUTES=15
CLAUDE_OUTPUT_FORMAT="json"

ALLOWED_TOOLS="Write,Read,Edit,Bash(git add *),Bash(git commit *),Bash(git diff *),Bash(git log *),Bash(git status),Bash(git status *),Bash(npm *),Bash(npx *),Bash(mkdir *),Bash(ls *)"

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
- **bash**: keep minimal

#### 4b. `.ralph/` directory

If `.ralph/` does NOT exist, create it:

Write `.ralph/fix_plan.md`:
```markdown
# Fix Plan — <PROJECT_NAME>

## Tasks

- [ ] Task 1: (adicionar tasks aqui)
```

Write `.ralph/AGENT.md`:
```markdown
# Agent Config — <PROJECT_NAME>

## Build
<commands based on PROJECT_TYPE — detect from package.json, Makefile, etc. if possible>

## Test
<commands based on PROJECT_TYPE>

## Run
<commands based on PROJECT_TYPE>
```

If AGENT.md can be auto-detected (e.g., read package.json scripts), populate it automatically.

#### 4c. `CLAUDE.md` (project governance)

If `CLAUDE.md` does NOT exist, create it:

```markdown
# <PROJECT_NAME>
## Governance

This project runs under **AI-Brain Engine v2** motor.
Motor root: `../../` (relative to this project)

## Tech Stack
<based on PROJECT_TYPE and detected dependencies>

## Key Commands
- Run Ralph: `cd <MOTOR_ROOT> && ./ralph-loop.sh <PROJECT_NAME>`
- Validate: `cd <MOTOR_ROOT> && ./validate.sh <PROJECT_NAME>`
- Skinner Status: From motor, run `/skinner-status <PROJECT_NAME>`

## Directory Structure
<detect and document existing structure>

## Language
- Docs in PT-BR
- Code in English
```

#### 4d. `.gitignore` additions

If `.gitignore` exists, append motor-specific entries (if not already present):
```
# Motor worktrees (Skinner)
.worktrees/
```

If `.gitignore` does NOT exist, create a standard one for the project type.

### 5. Add `.worktrees/` to project's `.gitignore`

Skinner creates worktrees inside the project. Make sure they're ignored:
```bash
echo ".worktrees/" >> "$PROJECT_DIR/.gitignore"  # if not already there
```

### 6. Create Missing Directories

Only create directories that don't exist and are appropriate:
- `specs/` — always (source of truth for the motor)
- `src/`, `tests/`, `docs/` — only for new projects (don't touch existing structure)

### 7. Commit Integration Files

If there are new files to commit:
```bash
cd "$PROJECT_DIR"
git add .ralphrc .ralph/ CLAUDE.md .gitignore
git commit -m "chore: integrate with AI-Brain Engine v2

Added motor integration files (.ralphrc, .ralph/, CLAUDE.md).
Motor: AI-Brain Engine v2
Type: <PROJECT_TYPE>"
```

### 8. Show Summary

Adapt output based on scenario:

**For existing project:**
```
Projeto configurado para o motor!

  Projeto: <PROJECT_NAME>
  Tipo: <PROJECT_TYPE> (detectado automaticamente)
  Local: workspace/<PROJECT_NAME>/
  Git: repositorio existente mantido

Arquivos adicionados:
  .ralphrc       — Config Ralph do projeto
  .ralph/        — Templates Ralph (fix_plan, AGENT)
  CLAUDE.md      — Governanca do projeto
  specs/         — Pasta de especificacoes (criada)

Proximos passos:
  1. Revise .ralphrc e ajuste ALLOWED_TOOLS se necessario
  2. Revise .ralph/AGENT.md e ajuste comandos de build/test
  3. Adicione tasks em .ralph/fix_plan.md
  4. Rode Ralph: ./ralph-loop.sh <PROJECT_NAME>
```

**For new project:**
```
Workspace criado com sucesso!

  Projeto: <PROJECT_NAME>
  Tipo: <PROJECT_TYPE>
  Local: workspace/<PROJECT_NAME>/
  Git: repositorio independente (novo)

Proximos passos:
  1. Adicione specs em workspace/<PROJECT_NAME>/specs/
  2. Adicione tasks em .ralph/fix_plan.md
  3. Rode Ralph: ./ralph-loop.sh <PROJECT_NAME>
```

## Language

- **ALL output MUST be in Brazilian Portuguese (PT-BR)**
