#!/usr/bin/env bash
# Create the loop's label vocabulary. Needs the gh CLI authenticated for the repo.
# Usage: AGENT_REPO=owner/repo ./scripts/setup-labels.sh   (or set AGENT_REPO in .env)
set -euo pipefail

[ -f .env ] && set -a && . ./.env && set +a
REPO="${AGENT_REPO:?set AGENT_REPO=owner/repo (env or .env)}"

mk(){ gh label create "$1" --repo "$REPO" --description "$2" --color "$3" --force; }

echo "Creating labels on $REPO ..."
mk "bug"                     "Intake: a defect to root-cause"                 "d73a4a"
mk "feature"                 "Intake: new work to plan"                       "0e8a16"
mk "triaged"                 "Triage worker posted a root cause (recommend-only)" "fbca04"
mk "ready"                   "HUMAN GATE: cleared to plan"                     "5319e7"
mk "plan-ready"              "Plan worker posted a plan; awaiting approval"    "1d76db"
mk "approved"                "HUMAN GATE: cleared to implement"               "5319e7"
mk "self-review-passed"      "Validate worker: evidence bundle clean"         "0e8a16"
mk "self-review-needs-fixes" "Validate worker: blocking findings"             "d73a4a"
echo "Done. Remember the gates are HUMAN-applied: 'ready' and 'approved'."
