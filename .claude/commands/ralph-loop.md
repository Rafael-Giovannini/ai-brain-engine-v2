---
description: "Run Ralph autonomous TDD loop with Skinner enforcement. Usage: /ralph-loop ghostfit [--max-loops 5] [--dry-run] [--prompt 'fix X']"
---

## User Input

```text
$ARGUMENTS
```

## Goal

Execute the Ralph autonomous development loop with Skinner enforcement for a given workspace.

## Instructions

1. **Parse input**: Extract workspace name and optional flags from user input.
   - First word = workspace name (e.g., `ghostfit`, `motor-financeiro`)
   - `--max-loops N` = limit loop count (default: 20)
   - `--dry-run` = simulate without executing
   - `--prompt "text"` = custom task instead of fix_plan.md

2. **If no workspace provided**, list available workspaces and ask user to pick one:
   ```bash
   # Check configs/ (centralized) and workspace/ (legacy) for configured projects
   for dir in configs/*/; do [ -f "$dir/.ralphrc" ] && basename "$dir"; done
   for dir in workspace/*/; do [ -f "$dir/.ralphrc" ] && basename "$dir"; done
   ```

3. **Build the command**:
   ```
   ./ralph-loop.sh <workspace> [--max-loops N] [--dry-run] [--prompt "text"]
   ```

4. **Run the command** using Bash from the repo root:
   ```bash
   cd /c/Users/rafael.giovannini/Documents/GitHub/ai-brain-engine-v2 && ./ralph-loop.sh <workspace> <flags>
   ```
   Use a timeout of 600000ms (10 min) since loops can take a while.

5. **After Ralph finishes**, report:
   - How many loops ran
   - How many tasks completed
   - Whether circuit breaker triggered
   - The worktree branch name for merge
   - VIGIL memory summary (if enabled)

6. **Post-loop validation (automatic)**:
   - Merge the Ralph worktree branch into the current branch: `git merge <ralph-branch>`
   - Run `/validate <workspace>` to check spec-vs-code consistency and code quality
   - Analyze the validation report results:
     - **If CRITICAL or HIGH issues found**:
       - Show the issues to the user
       - Ask: "Foram encontrados N issues CRITICAL/HIGH. Quer que eu rode outro loop do Ralph para corrigir?"
       - If yes: run another `./ralph-loop.sh <workspace> --prompt "Fix validation issues: <list of critical/high findings>"`
       - After the fix loop, merge and re-validate (repeat until clean or user stops)
     - **If only MEDIUM/LOW or no issues**: Report success and proceed to cleanup
   - Clean up the worktree: `git worktree remove <path> --force && git branch -D <branch>`

7. **Final summary**:
   - Total loops executed (including fix loops)
   - Total tasks completed
   - Validation status (PASS / issues remaining)
   - Link to the validation report file

## Language

- **ALL output MUST be in Brazilian Portuguese (PT-BR)**: status reports, summaries, questions, and all conversation with the user.
- Technical terms (file names, branch names, git commands, severity levels like CRITICAL/HIGH/MEDIUM/LOW) may remain in English.

## Examples

```
/ralph-loop ghostfit
/ralph-loop ghostfit --max-loops 3
/ralph-loop motor-financeiro --dry-run
/ralph-loop ghostfit --prompt "fix the encryption test"
```
