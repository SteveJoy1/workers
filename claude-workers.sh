#!/usr/bin/env bash
# claude-workers.sh — Primary Claude oversees parallel Claude workers
#
# Usage:
#   ./claude-workers.sh tasks.txt           # one task per line
#   ./claude-workers.sh "task1" "task2" ...  # tasks as arguments
#
# Environment:
#   MAX_PARALLEL=4        Max concurrent workers (default: 4)
#   MODEL=claude-opus-4-6 Claude model for workers + reviewer (default: CLI default)
#   TOOLS="Edit,Bash,Read" Allowed tools for workers (default: all)
#   REVIEW_PROMPT=""      Custom instructions for the primary reviewer
#   SKIP_REVIEW=1         Skip the primary review phase
#   OUTPUT_DIR=...        Where worker results are saved

set -euo pipefail

MAX_PARALLEL="${MAX_PARALLEL:-6}"
MODEL="${MODEL:-}"
MODEL_FLAG=""
[[ -n "$MODEL" ]] && MODEL_FLAG="--model $MODEL"
TOOLS="${TOOLS:-}"
TOOLS_FLAG=""
[[ -n "$TOOLS" ]] && TOOLS_FLAG="--allowedTools $TOOLS"
OUTPUT_DIR="${OUTPUT_DIR:-.claude-workers-output}"
REVIEW_PROMPT="${REVIEW_PROMPT:-}"
SKIP_REVIEW="${SKIP_REVIEW:-0}"
mkdir -p "$OUTPUT_DIR"

tasks=()

# Load tasks from file or arguments
if [[ $# -eq 1 && -f "$1" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" && ! "$line" =~ ^# ]] && tasks+=("$line")
  done < "$1"
else
  tasks=("$@")
fi

if [[ ${#tasks[@]} -eq 0 ]]; then
  echo "Usage: $0 tasks.txt"
  echo "       $0 \"task one\" \"task two\" ..."
  exit 1
fi

# ── Phase 1: Fan-out — run workers in parallel ──────────────────────

echo "═══ Phase 1: Dispatching ${#tasks[@]} worker(s) (max $MAX_PARALLEL parallel) ═══"

pids=()

run_worker() {
  local id=$1
  local task=$2
  local outfile="$OUTPUT_DIR/worker-${id}.md"

  echo "[worker $id] Starting: ${task:0:60}..."
  claude -p "$task" $MODEL_FLAG $TOOLS_FLAG --output-format text > "$outfile" 2>&1
  echo "[worker $id] Done → $outfile"
}

active=0
for i in "${!tasks[@]}"; do
  run_worker "$i" "${tasks[$i]}" &
  pids+=($!)
  active=$((active + 1))

  if [[ $active -ge $MAX_PARALLEL ]]; then
    wait "${pids[0]}"
    pids=("${pids[@]:1}")
    active=$((active - 1))
  fi
done

for pid in "${pids[@]}"; do
  wait "$pid"
done

echo ""
echo "All ${#tasks[@]} workers finished."

# ── Phase 2: Fan-in — primary Claude reviews all results ────────────

if [[ "$SKIP_REVIEW" == "1" ]]; then
  echo "Skipping review (SKIP_REVIEW=1). Results in $OUTPUT_DIR/"
  exit 0
fi

echo ""
echo "═══ Phase 2: Primary Claude reviewing worker outputs ═══"

# Build a combined prompt with each worker's task + output
review_input=""
for i in "${!tasks[@]}"; do
  outfile="$OUTPUT_DIR/worker-${i}.md"
  if [[ -f "$outfile" ]]; then
    review_input+="
--- Worker $i ---
Task: ${tasks[$i]}
Output:
$(cat "$outfile")
"
  fi
done

default_review="You are a primary overseer reviewing work from multiple Claude workers.
For each worker's output:
1. Assess correctness and completeness
2. Flag any errors, conflicts, or gaps between workers
3. Provide a final synthesized summary or verdict

If any worker's output is insufficient, list the specific follow-up tasks needed."

primary_prompt="${REVIEW_PROMPT:-$default_review}

Here are the worker results to review:
$review_input"

claude -p "$primary_prompt" $MODEL_FLAG $TOOLS_FLAG --output-format text | tee "$OUTPUT_DIR/primary-review.md"

echo ""
echo "═══ Done. Review saved to $OUTPUT_DIR/primary-review.md ═══"
