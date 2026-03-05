---
description: "Check Skinner status: active worktrees, Ralph branches, recent logs, VIGIL memory, and pending merges. Usage: /skinner-status [workspace]"
---

## User Input

```text
$ARGUMENTS
```

## Goal

Show the current status of Skinner enforcement: active worktrees, Ralph branches, session logs, VIGIL behavioral memory, and pending merges.

## Instructions

1. **Show active worktrees**:
   ```bash
   cd /c/Users/rafael.giovannini/Documents/GitHub/ai-brain-engine-v2 && git worktree list
   ```

2. **Show Ralph branches** (unmerged):
   ```bash
   git branch --list "ralph/*" --no-merged
   ```

3. **Show recent session logs** (if workspace provided, filter by it):
   - If workspace argument given:
     ```bash
     ls -lt .skinner/logs/<workspace>/ | head -5
     ```
   - Otherwise:
     ```bash
     find .skinner/logs/ -name "session-*.log" -type f | sort -r | head -10
     ```

4. **For each active ralph worktree**, show:
   - Branch name
   - Commit count ahead of current branch: `git log HEAD..<branch> --oneline`
   - Whether it has uncommitted changes

5. **Show last log tail** (most recent session):
   - Read the last 30 lines of the most recent log file

6. **VIGIL Memory Summary** (if .skinner/memory/vigil.jsonl exists):
   - Count total errors recorded
   - Show error type distribution (TEST_FAILURE, NO_PROGRESS, HALLUCINATION, REVERT, CIRCUIT_BREAKER)
   - Show most recent 5 errors
   - Show Roses/Buds/Thorns summary if available

7. **Engine layer status** (from engine.yaml):
   - Show which layers are enabled/disabled

8. **Suggest actions**:
   - If unmerged ralph branches exist: "Run `git merge <branch>` to incorporate Ralph's work"
   - If worktrees exist with no new commits: "Run `git worktree remove <path> --force` to clean up"
   - If worktrees have uncommitted changes: "Review and commit or discard changes"
   - If VIGIL shows repeated errors: "Consider reviewing and addressing recurring patterns"

## Language

- **ALL output MUST be in Brazilian Portuguese (PT-BR)**

## Examples

```
/skinner-status
/skinner-status ghostfit
```
