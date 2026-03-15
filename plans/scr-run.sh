#!/usr/bin/env bash
# scr-run.sh — Execute the full SCR work plan in phases
# Each phase waits for your approval before proceeding to the next.
#
# Usage: ./plans/scr-run.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKERS="$SCRIPT_DIR/../claude-workers.sh"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║        SCR Work Plan — 3-Phase Worker Pipeline          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# ── Phase 1: Specialist Reviews ─────────────────────────────────
echo "━━━ PHASE 1: Specialist Analysis & Review ━━━"
echo "5 specialists will review the SCR codebase in parallel."
echo ""

export REVIEW_PROMPT="You are the PRIMARY OVERSEER for Steve's Running Coach (SCR).
You have received reports from 5 specialists: a statistician, exercise physiologist,
training periodization expert, predictive modeling expert, and software architect.

Your job:
1. Synthesize their findings into a unified assessment.
2. Flag any CONFLICTS between specialist recommendations.
3. Identify any issues that would BLOCK Phase 2 implementation.
4. Produce a final GO/NO-GO recommendation for each of the 5 pipeline gaps.
5. Note any formula or methodology changes the specialists recommend
   that should be applied BEFORE implementation begins.

Format your response as an actionable brief, not a summary of summaries."

"$WORKERS" "$SCRIPT_DIR/scr-phase1-analysis.txt"

echo ""
echo "Review the Phase 1 results in .claude-workers-output/"
echo "primary-review.md has the overseer's synthesis."
read -rp "Proceed to Phase 2 (Implementation)? [y/N] " proceed
[[ "$proceed" =~ ^[Yy] ]] || { echo "Stopped after Phase 1."; exit 0; }

# ── Phase 2: Implementation ─────────────────────────────────────
echo ""
echo "━━━ PHASE 2: Implementation (4 parallel workers) ━━━"
echo "Each worker implements one pipeline gap."
echo ""

export REVIEW_PROMPT="You are the PRIMARY OVERSEER reviewing implementation work from 4 workers.
Each worker implemented a different pipeline gap in SCR.

Your job:
1. Check for CONFLICTS between workers (did they modify the same files/functions?).
2. Verify each worker wrote tests.
3. Flag any changes that contradict the Phase 1 specialist recommendations.
4. List the exact files modified by each worker so we can review diffs.
5. Identify any MERGE ORDER dependencies (e.g., Gap 1 must land before Gap 3).

Format as a merge plan with recommended order."

"$WORKERS" "$SCRIPT_DIR/scr-phase2-implement.txt"

echo ""
echo "Review the Phase 2 results in .claude-workers-output/"
read -rp "Proceed to Phase 3 (Validation)? [y/N] " proceed
[[ "$proceed" =~ ^[Yy] ]] || { echo "Stopped after Phase 2."; exit 0; }

# ── Phase 3: Integration & Validation ───────────────────────────
echo ""
echo "━━━ PHASE 3: Integration & Validation (3 workers) ━━━"
echo "Workers verify the full pipeline after implementation."
echo ""

export REVIEW_PROMPT="You are the PRIMARY OVERSEER performing final validation.
You have reports from an integration tester, physiologist validator, and statistician validator.

Your job:
1. Are all tests passing?
2. Are there any physiologically unsound recommendations the system could produce?
3. Are there statistical concerns (overfitting, numerical instability)?
4. FINAL VERDICT: Is the implementation ready for use, or does it need revisions?
5. If revisions needed, list specific tasks for a follow-up Phase 2b."

"$WORKERS" "$SCRIPT_DIR/scr-phase3-integrate.txt"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                  All phases complete.                   ║"
echo "║  Results: .claude-workers-output/primary-review.md      ║"
echo "╚══════════════════════════════════════════════════════════╝"
