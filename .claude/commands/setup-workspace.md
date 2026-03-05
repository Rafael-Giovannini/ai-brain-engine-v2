---
description: "Inicializar um novo projeto no workspace/ do motor. Cria repo git independente com .ralphrc, CLAUDE.md e estrutura basica. Usage: /setup-workspace <nome> [--type node|python|java|bash] [--desc 'descricao']"
---

## User Input

```text
$ARGUMENTS
```

## Goal

Inicializar um novo projeto dentro de `workspace/` do motor AI-Brain Engine v2.
O projeto sera um **repositorio git independente** (nested repo), nao parte do motor.

## Instructions

### 1. Parse Arguments

Extract from user input:
- `PROJECT_NAME` (required) — nome do projeto (ex: ghostfit, marketplace, api-gateway)
- `PROJECT_TYPE` (optional, default: node) — tipo: node, python, java, bash
- `PROJECT_DESC` (optional) — descricao curta do projeto

### 2. Validate

- Check that `workspace/` directory exists (create if not)
- Check that `workspace/<PROJECT_NAME>/` does NOT already exist
- If it exists, ask user if they want to overwrite

### 3. Create Project Structure

```bash
MOTOR_ROOT=$(pwd)
PROJECT_DIR="$MOTOR_ROOT/workspace/<PROJECT_NAME>"

mkdir -p "$PROJECT_DIR"/{src,tests,docs,specs}
```

### 4. Initialize Git Repo

```bash
cd "$PROJECT_DIR"
git init
```

### 5. Create .ralphrc (project-specific)

Write `$PROJECT_DIR/.ralphrc` with:

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

### 6. Create Project CLAUDE.md

Write `$PROJECT_DIR/CLAUDE.md` with project-specific governance:

```markdown
# <PROJECT_NAME>
## Governance

This project runs under **AI-Brain Engine v2** motor.
Motor root: `../../` (relative to this project)

## Tech Stack
<based on PROJECT_TYPE>

## Key Commands
- Run Ralph: `cd <MOTOR_ROOT> && ./ralph-loop.sh <PROJECT_NAME>`
- Validate: `cd <MOTOR_ROOT> && ./validate.sh <PROJECT_NAME>`
- Skinner Status: From motor, run `/skinner-status <PROJECT_NAME>`

## Directory Structure
- `src/` — Source code
- `tests/` — Test files
- `docs/` — Project documentation
- `specs/` — Specifications (source of truth)

## Language
- Docs in PT-BR
- Code in English
```

### 7. Create .ralph/ Override (project-specific)

Copy Ralph templates from motor and customize:

```bash
mkdir -p "$PROJECT_DIR/.ralph"
```

Write `$PROJECT_DIR/.ralph/fix_plan.md`:
```markdown
# Fix Plan — <PROJECT_NAME>

## Tasks

- [ ] Task 1: Setup inicial do projeto
- [ ] Task 2: (adicionar tasks aqui)
```

Write `$PROJECT_DIR/.ralph/AGENT.md`:
```markdown
# Agent Config — <PROJECT_NAME>

## Build
<commands based on PROJECT_TYPE>

## Test
<commands based on PROJECT_TYPE>

## Run
<commands based on PROJECT_TYPE>
```

### 8. Create .gitignore for the project

Write `$PROJECT_DIR/.gitignore`:
```
node_modules/
dist/
build/
.env
.env.local
__pycache__/
*.pyc
.venv/
.DS_Store
Thumbs.db
```

### 9. Initial Commit

```bash
cd "$PROJECT_DIR"
git add -A
git commit -m "chore: initial project setup via AI-Brain Engine v2

Initialized by /setup-workspace skill.
Motor: AI-Brain Engine v2
Type: <PROJECT_TYPE>"
```

### 10. Show Summary

```
Workspace criado com sucesso!

  Projeto: <PROJECT_NAME>
  Tipo: <PROJECT_TYPE>
  Local: workspace/<PROJECT_NAME>/
  Git: repositorio independente (nested repo)

Estrutura:
  workspace/<PROJECT_NAME>/
    src/           — Codigo fonte
    tests/         — Testes
    docs/          — Documentacao
    specs/         — Especificacoes
    .ralph/        — Config Ralph (override)
    .ralphrc       — Config do projeto
    CLAUDE.md      — Governanca do projeto
    .gitignore     — Git ignore

Proximos passos:
  1. Adicione specs em workspace/<PROJECT_NAME>/specs/
  2. Adicione tasks em workspace/<PROJECT_NAME>/.ralph/fix_plan.md
  3. Rode Ralph: ./ralph-loop.sh <PROJECT_NAME>
  4. Ou abra o projeto diretamente: cd workspace/<PROJECT_NAME>
```

## Language

- **ALL output MUST be in Brazilian Portuguese (PT-BR)**
