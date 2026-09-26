#!/usr/bin/env bash
# Structural-drift check — operationalizes "one fact, one home" (§14).
#
# .claude/ is the single source of truth (the only tracked home). Some platforms keep an
# OPTIONAL generic mirror under .agents/ (and Codex exports under .codex/). Those mirrors are
# not required — but if one EXISTS it must be byte-identical to its .claude source, because a
# divergent copy is exactly the "two homes, two truths" failure §14 warns about. The kit also
# repeats one security-critical shell block across the two optional cloud workflows; that block
# must stay in sync. This script asserts those invariants and exits non-zero on any drift, so it
# can run in CI and is wired into the preflight (Gate 6).
#
# An ABSENT mirror is fine (it can't diverge); a PRESENT-but-different mirror is drift. It is
# NOT a generator — it does not rewrite anything, only detects divergence.
set -uo pipefail

drift=0
ok(){   printf '  [ok]   %s\n' "$1"; }
bad(){  printf '  [FAIL] %s\n' "$1"; drift=1; }
skip(){ printf '  [skip] %s\n' "$1"; }

# 1) Optional skill mirrors: present => must match the canonical .claude source.
check_mirror(){ # $1 canonical  $2 optional-mirror  $3 label
  if [ ! -f "$1" ]; then
    bad "$3: canonical source missing ($1)"
  elif [ ! -f "$2" ]; then
    skip "$3: no mirror at $2 (optional)"
  elif diff -q "$1" "$2" >/dev/null 2>&1; then
    ok "$3 mirror in sync"
  else
    bad "$3 DRIFTED — $2 differs from canonical $1 (regenerate the mirror or delete it)"
  fi
}
check_mirror .claude/skills/agent-loop/SKILL.md     .agents/skills/agent-loop/SKILL.md     "agent-loop skill"
check_mirror .claude/skills/dev-validation/SKILL.md .agents/skills/dev-validation/SKILL.md "dev-validation skill"

# 2) The human-gate allowlist block must be EQUIVALENT across BOTH optional workflows — not just
#    "contains the right fragments". We extract the bounded shell block (set -euo pipefail .. the
#    first exit 1), normalize the only intended differences (the gate label `ready`/`approved`
#    and the verb `plan`/`implement`), and diff. Any drift in the surrounding fail/allow logic
#    then fails the check, which a fragment grep would miss.
extract_gate(){ # $1 workflow -> normalized gate block on stdout (empty if absent)
  [ -f "$1" ] || return 0
  awk '/set -euo pipefail/{f=1} f{print} /exit 1/{if(f) exit}' "$1" \
    | sed -E "s/^[[:space:]]+//; s/'(ready|approved)'/'GATE'/g; s/refusing to (plan|implement)/refusing to VERB/g"
}
PLAN_WF=optional/cloud-triggers/agent-plan.yml
IMPL_WF=optional/cloud-triggers/agent-implement.yml
plan_gate=$(extract_gate "$PLAN_WF")
impl_gate=$(extract_gate "$IMPL_WF")
# Absent vs broken are different. If NEITHER optional workflow exists, the operator opted out of
# cloud triggers and there is nothing to drift, so skip, the same way a missing skill mirror is
# skipped above. That is not an unverified boundary: the component does not exist by design.
# Everything else stays fail-closed: exactly one workflow present means a half-installed trigger,
# and a present workflow whose gate block cannot be extracted means a trigger that could act
# without its gate check. Both are failures, never skips.
if [ ! -f "$PLAN_WF" ] && [ ! -f "$IMPL_WF" ]; then
  skip "gate-check block: no optional cloud-trigger workflows installed (optional)"
elif [ ! -f "$PLAN_WF" ] || [ ! -f "$IMPL_WF" ]; then
  bad "only one optional cloud-trigger workflow is installed; install both or neither (the gate block must exist in each)"
elif [ -z "$plan_gate" ] || [ -z "$impl_gate" ]; then
  bad "gate-check block not found in one of the optional workflows (expected 'set -euo pipefail .. exit 1')"
elif [ "$plan_gate" = "$impl_gate" ]; then
  ok "gate-check block identical across both optional workflows ($(printf '%s\n' "$plan_gate" | grep -c .) lines)"
else
  bad "gate-check block DRIFTED between agent-plan.yml and agent-implement.yml:"
  diff <(printf '%s\n' "$plan_gate") <(printf '%s\n' "$impl_gate") | sed 's/^/      /'
fi

if [ "$drift" -ne 0 ]; then
  echo "DRIFT DETECTED — mirrored knowledge has diverged."
  exit 1
fi
echo "no drift — mirrors in sync."
