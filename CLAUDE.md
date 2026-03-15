# Claude Workers — Orchestration Pattern

## What This Is

`claude-workers.sh` is a fan-out/fan-in orchestrator: dispatch N parallel Claude
workers (each a separate `claude -p` process), collect outputs, then optionally
run a reviewer over all results.

**The orchestrator (you) should do as little as possible directly.** Delegate all
code changes, testing, and review to workers. You stay high-level: design phases,
write prompts, read outputs, chain phases, and make go/no-go decisions.

## Quick Start

```bash
# From a project directory:
~/Developer/workers/claude-workers.sh "task one" "task two" "task three"

# Or from a task file (one task per line, # comments ignored):
~/Developer/workers/claude-workers.sh tasks.txt
```

## Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `MAX_PARALLEL` | 6 | Max concurrent workers |
| `MODEL` | (CLI default) | Claude model for all workers + reviewer |
| `TOOLS` | (all) | Allowed tools, e.g. `Edit,Bash,Read,Write,Glob,Grep` |
| `OUTPUT_DIR` | `.claude-workers-output` | Where worker results are saved |
| `REVIEW_PROMPT` | (built-in) | Custom instructions for the reviewer |
| `SKIP_REVIEW` | 0 | Set to `1` to skip the fan-in review phase |

## Orchestration Pattern

### Single Phase

```bash
OUTPUT_DIR=.claude-workers-output/phase1 SKIP_REVIEW=1 \
  ~/Developer/workers/claude-workers.sh tasks.txt
```

### Multi-Phase Pipeline

The standard pattern: edit → verify → review, with orchestrator approval gates
between phases.

1. **Phase 1 — Foundation** (serial): Shared utilities, imports, schema changes
2. **Phase 2 — Parallel edits** (parallel): Independent workers, one file per worker
3. **Phase 3 — Integration** (serial or parallel): Wire components together
4. **Phase 4 — Review** (parallel): Statistician + domain expert verify changes
5. **Phase 5 — Documentation** (serial): Update docs, findings, architecture

Between each phase, the orchestrator reads outputs, verifies, and decides whether
to proceed or fix issues.

### Approval Gates

After each phase:
1. Read worker outputs
2. Syntax-check modified files: `python3 -c "import ast; ast.parse(open('file.py').read())"`
3. Import-check: `python3 -c "import app"` (or relevant module)
4. Decide: proceed to next phase, or dispatch fix workers

## Worker Prompt Best Practices

### Must Include

1. **Working directory**: `You are a code worker in /path/to/project.`
2. **Files to read first**: Name the specific files and approximate line ranges
3. **Exact scope**: One file, one function, one change per worker
4. **Constraints**: `Use numpy only (no sklearn)`, preserve existing code, etc.
5. **Verification**: `Show before/after`, `Report PASS/FAIL with line numbers`

### Good Prompt

```
You are a code worker in /Users/stevejoy/Developer/SCR. Add leave-one-out
cross-validation to calibrate_banister() in physiology.py (lines 408-552).
After the OLS fit, add a LOO-CV step: for each data point, refit OLS on N-1
points, predict the held-out point. Compute CV R² and CV RMSE. Store results
in the returned dict under 'cv_diagnostics'. Use numpy only. Read the file
first, preserve all existing code.
```

### Bad Prompt

```
Fix the cross-validation in the project.
```

### Critical: Task File Format

- **One task per line** — multi-line tasks get split into separate workers
- `#` lines are ignored (comments)
- For complex multi-line prompts, pass as a quoted argument instead:
  ```bash
  ~/Developer/workers/claude-workers.sh "Your long prompt here..."
  ```

## Review Pattern

Use dedicated review workers — a worker should never grade its own homework.

```bash
# Edit phase (skip review)
SKIP_REVIEW=1 OUTPUT_DIR=.claude-workers-output/edits \
  ~/Developer/workers/claude-workers.sh edit-tasks.txt

# Review phase (with domain-specific review prompt)
REVIEW_PROMPT="Check all formulas for mathematical correctness. Report PASS/FAIL per file." \
  OUTPUT_DIR=.claude-workers-output/review \
  ~/Developer/workers/claude-workers.sh review-tasks.txt
```

### Parallel Reviewers

Send different reviewers in parallel for cross-domain validation:

```
# review-tasks.txt
You are a statistician. Verify all R² formulas, LOO-CV implementation, VIF computation...
You are a physiologist. Check time constants, HR zone thresholds, model assumptions...
```

## Model Selection

| Task Type | Recommended Model | Why |
|---|---|---|
| Architecture, cross-cutting refactors | Opus | Needs broad context |
| Statistical/mathematical review | Opus | Needs deep reasoning |
| Focused single-file implementation | Sonnet | Fast, accurate for scoped work |
| Documentation, formatting | Sonnet or Haiku | Low complexity |

```bash
# Opus for review phases
MODEL=claude-opus-4-6 ~/Developer/workers/claude-workers.sh review-tasks.txt

# Sonnet for implementation phases
MODEL=claude-sonnet-4-6 SKIP_REVIEW=1 ~/Developer/workers/claude-workers.sh edit-tasks.txt
```

## Tool Permissions

| Worker Type | Recommended Tools |
|---|---|
| Code editor | `Edit,Read,Glob,Grep,Bash,Write` |
| Reviewer (read-only) | `Read,Glob,Grep,Bash` |
| Test runner | `Bash,Read,Glob,Grep` |
| Documentation writer | `Edit,Read,Write,Glob,Grep` |

```bash
TOOLS="Edit,Read,Glob,Grep,Bash,Write" ~/Developer/workers/claude-workers.sh tasks.txt
```

## Common Pitfalls

1. **Newline splitting**: Multi-line task in a file → each line becomes a separate
   worker. Use quoted arguments or single-line tasks.

2. **Parallel file conflicts**: Two workers editing the same file → last writer wins.
   **Rule: one file per worker in parallel phases.** If multiple workers must touch
   the same file, run them sequentially or in separate phases.

3. **No shared context**: Each worker starts cold. For large projects, consider
   prefixing prompts with key constraints and file summaries.

4. **Workers claiming success**: A worker's prose output may say "Done!" even if
   the edit failed. Always verify with `ast.parse()`, `import`, or `git diff`.

5. **Review reads prose, not code**: The built-in reviewer reads worker output
   text, not the actual file state. Supplement with deterministic checks.

6. **Forgetting SKIP_REVIEW**: Edit phases usually don't need the built-in
   reviewer (you'll review outputs yourself). Set `SKIP_REVIEW=1` for speed.

## Example: Multi-Phase Pipeline (SCR Project)

```bash
# Phase 1: Foundation (serial — shared utilities)
SKIP_REVIEW=1 OUTPUT_DIR=.claude-workers-output/phase1 \
  ~/Developer/workers/claude-workers.sh "Create validation.py with LOO-CV, VIF, walk-forward utilities..."

# Phase 2: Parallel edits (4 workers, independent files)
SKIP_REVIEW=1 OUTPUT_DIR=.claude-workers-output/phase2 \
  ~/Developer/workers/claude-workers.sh phase2-tasks.txt

# Orchestrator verifies: read outputs, syntax check, import check

# Phase 3: Integration (wires components together)
SKIP_REVIEW=1 OUTPUT_DIR=.claude-workers-output/phase3 \
  ~/Developer/workers/claude-workers.sh "Wire walk-forward validation into the Analysis tab..."

# Phase 4: Parallel review (statistician + physiologist)
MODEL=claude-opus-4-6 OUTPUT_DIR=.claude-workers-output/phase4 \
  ~/Developer/workers/claude-workers.sh phase4-review.txt

# Phase 5: Documentation
SKIP_REVIEW=1 OUTPUT_DIR=.claude-workers-output/phase5 \
  ~/Developer/workers/claude-workers.sh "Document all findings in STATISTICAL_FINDINGS.md..."
```

## Future Improvements

- **Git worktrees per worker**: Eliminate file conflict risk entirely
- **Per-task model selection**: `opus: Review formulas` / `sonnet: Add function`
- **Context pre-loading**: `CONTEXT_FILE=.claude-workers-context.md` prepended to all prompts
- **Exit code checking + retry**: Detect failed workers and retry once
- **Automated verification gates**: `ast.parse`, import check, test suite between phases
