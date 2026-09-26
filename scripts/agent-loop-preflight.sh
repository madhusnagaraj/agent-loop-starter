#!/usr/bin/env bash
# Preflight — verify the human gates AND the credential boundary are real BEFORE the loop
# is allowed to run. Exit non-zero => the loop must NOT run. The poll command runs this first
# and aborts on failure, so the loop self-disables until it's safe.
#
# This is the executable form of the §13 activation checklist: every load-bearing row is a
# gate here. Controls this script cannot probe from outside the app (the content controls) are
# turned into an explicit operator ATTESTATION rather than silently skipped — fail-closed, so
# "PREFLIGHT PASSED" can never mean "a non-negotiable was skipped".
#
# Read-only: GitHub API reads + one secret probe that is EXPECTED to be denied (never prints
# secret values). Run it under the SCOPED loop identity (e.g. AWS_PROFILE=agent-loop, and gh
# authenticated AS the bot) so the identity + credential probes are meaningful — under an admin
# identity the write-secret read will succeed and this will (correctly) fail.
#
# Config via env or .env: AGENT_REPO, AGENT_BASE_BRANCH, AGENT_BOT_LOGIN, AGENT_GATE_MAINTAINERS,
# AGENT_DENY_SECRET, AGENT_READ_SECRET, AWS_REGION, AGENT_SECRET_PROBE_CMD,
# AGENT_CONTENT_CONTROLS_ACK, AGENT_AUDIT_PATHS.
set -uo pipefail

[ -f .env ] && set -a && . ./.env && set +a

REPO="${AGENT_REPO:-owner/repo}"
BRANCH="${AGENT_BASE_BRANCH:-main}"
DENY_SECRET="${AGENT_DENY_SECRET:-app-write-credentials}"
READ_SECRET="${AGENT_READ_SECRET:-app-readonly-credentials}"
REGION="${AWS_REGION:-us-east-1}"
MAINTAINERS="${AGENT_GATE_MAINTAINERS:-}"

fail=0
pass(){ printf '  [PASS] %s\n' "$1"; }
bad(){ printf '  [FAIL] %s\n' "$1"; fail=1; }
info(){ printf '  [info] %s\n' "$1"; }

echo "agent-loop preflight — repo=$REPO branch=$BRANCH"

# Gate 1 — branch protection requires a human review
echo "[1/7] merge gate (required reviews >= 1)"
rev=""
if revraw=$(gh api "repos/$REPO/branches/$BRANCH/protection/required_pull_request_reviews" \
  --jq '.required_approving_review_count' 2>/dev/null); then rev="$revraw"; fi
if [ -n "$rev" ] && [ "$rev" -ge 1 ] 2>/dev/null; then
  pass "required_approving_review_count = $rev"
else
  bad "required_approving_review_count = ${rev:-<none>} (need >= 1)"
fi

# Gate 2 — dedicated worker identity: the active token must BE the bot, the bot must NOT be a
# gate maintainer (else it could open its own gate), and it must not hold repo admin.
echo "[2/7] dedicated bot identity"
bot="${AGENT_BOT_LOGIN:-}"
if [ -z "$bot" ]; then
  bot=$(gh api "repos/$REPO/actions/variables/AGENT_BOT_LOGIN" --jq '.value' 2>/dev/null || true)
fi
if [ -z "$MAINTAINERS" ]; then
  MAINTAINERS=$(gh api "repos/$REPO/actions/variables/AGENT_GATE_MAINTAINERS" --jq '.value' 2>/dev/null || true)
fi
# A login may contain only [A-Za-z0-9._-] plus the App-bot brackets; if a fallback returned an
# error body or other junk (e.g. a 404 JSON blob), discard it so it can't masquerade as a login.
case "$bot" in *[!A-Za-z0-9._\[\]-]*) bot="" ;; esac
case "$MAINTAINERS" in *[!A-Za-z0-9._,\[\]-]*) MAINTAINERS="" ;; esac
if [ -z "$bot" ]; then
  bad "no AGENT_BOT_LOGIN set (env or repo variable)"
else
  me=$(gh api user --jq '.login' 2>/dev/null || true)
  if [ -z "$me" ]; then
    bad "could not resolve the authenticated GitHub identity (is gh logged in as the bot?)"
  elif [ "$me" != "$bot" ]; then
    bad "active token is '$me', not the bot '$bot' — run the loop as its dedicated identity"
  else
    pass "running as the dedicated bot identity '$bot'"
  fi
  # The worker must never be on the human gate allowlist.
  case ",${MAINTAINERS}," in
    *",${bot},"*) bad "bot '$bot' is on AGENT_GATE_MAINTAINERS — it could open its own gate; remove it" ;;
    *)
      if [ -n "$MAINTAINERS" ]; then
        pass "bot is not a gate maintainer"
      else
        bad "AGENT_GATE_MAINTAINERS unset — cannot confirm the bot is off the allowlist; refusing rather than assuming"
      fi
      ;;
  esac
  # The worker must not be over-privileged on the repo. Fail-closed: pass ONLY when we can read
  # the permission and it is explicitly false; an unreadable result is an unverified boundary.
  admin=$(gh api "repos/$REPO" --jq '.permissions.admin' 2>/dev/null || true)
  if [ "$admin" = "false" ]; then
    pass "bot does not hold repo admin"
  elif [ "$admin" = "true" ]; then
    bad "bot '$bot' has admin on $REPO — too privileged for a worker identity"
  else
    bad "could not confirm the bot lacks repo admin (.permissions.admin unreadable) — refusing rather than assuming"
  fi
fi

# Gate 3 — label-guard workflow present on the branch
echo "[3/7] label-guard workflow"
if gh api "repos/$REPO/contents/.github/workflows/agent-gate-guard.yml?ref=$BRANCH" --jq '.path' >/dev/null 2>&1; then
  pass "agent-gate-guard.yml present on $BRANCH"
else
  bad "agent-gate-guard.yml not found on $BRANCH"
fi

# Gate 4 — credential isolation: the write/admin secret MUST be denied to this identity.
# Fail-closed: if we cannot run a probe that proves the deny, this gate FAILS. A missing aws
# CLI is not "nothing to check" — it means the boundary is unverified. Point a custom store at
# AGENT_SECRET_PROBE_CMD (exit 0 only when the privileged secret is confirmed DENIED).
echo "[4/7] credential isolation (write-secret must be denied)"
if [ -n "${AGENT_SECRET_PROBE_CMD:-}" ]; then
  if probeout=$(bash -c "$AGENT_SECRET_PROBE_CMD" 2>&1); then
    pass "secret-store adapter confirmed the write boundary is denied"
  else
    bad "secret-store adapter could NOT confirm the deny ($(printf '%s' "$probeout" | tr '\n' ' ' | head -c 80))"
  fi
elif command -v aws >/dev/null 2>&1; then
  if errout=$(aws secretsmanager get-secret-value --region "$REGION" \
      --secret-id "$DENY_SECRET" --query 'Name' --output text 2>&1 >/dev/null); then
    bad "READ the write secret '$DENY_SECRET' — this identity is too privileged"
  elif printf '%s' "$errout" | grep -qiE "AccessDenied|not authorized|explicit deny"; then
    pass "write secret '$DENY_SECRET' is denied (boundary working)"
  else
    bad "could not confirm deny on '$DENY_SECRET' ($(printf '%s' "$errout" | tr '\n' ' ' | head -c 80))"
  fi
  if aws secretsmanager get-secret-value --region "$REGION" --secret-id "$READ_SECRET" \
      --query 'Name' --output text >/dev/null 2>&1; then
    info "read-only secret '$READ_SECRET' reachable (expected)"
  else
    info "read-only secret '$READ_SECRET' NOT reachable — check the loop identity has read access"
  fi
else
  bad "no credential-store adapter to prove the write boundary is denied — install the aws CLI under the scoped identity, or set AGENT_SECRET_PROBE_CMD for your store. Refusing to pass on an unverified boundary."
fi

# Gate 5 — content controls. The preflight CANNOT probe these from outside the app (they live
# in your send path / data layer), so it requires an explicit operator attestation instead of
# silently passing. This is what keeps the checklist and the runtime check the same thing.
echo "[5/7] content controls (operator attestation — not externally probeable)"
controls="fail-closed outbound side-effect fence; synthetic-only data provenance; structural-drift detection"
if [ "${AGENT_CONTENT_CONTROLS_ACK:-}" = "1" ]; then
  pass "operator attests content controls are wired & active ($controls)"
else
  bad "content controls not attested — these live in your app, not this kit: $controls. Wire them, then set AGENT_CONTENT_CONTROLS_ACK=1 to assert they are active."
fi

# Gate 6 — structural drift: mirrored knowledge ("one fact, one home") must stay in sync.
echo "[6/7] structural drift (mirrored knowledge in sync)"
if [ -f scripts/agent-loop-drift-check.sh ]; then
  if driftout=$(bash scripts/agent-loop-drift-check.sh 2>&1); then
    pass "no structural drift"
  else
    bad "structural drift detected — run scripts/agent-loop-drift-check.sh"
    printf '%s\n' "$driftout" | sed 's/^/      /'
  fi
else
  bad "scripts/agent-loop-drift-check.sh missing — cannot verify mirrored knowledge is in sync"
fi

# Gate 7 — config audit: the agent configuration itself must not carry a secret, grant a
# read-only reviewer write access, or feed untrusted input into a shell. Static, like Gate 6.
echo "[7/7] config audit (no secrets / least-privilege agents / no injected shell input)"
if [ -f scripts/agent-loop-config-audit.sh ]; then
  if auditout=$(bash scripts/agent-loop-config-audit.sh 2>&1); then
    pass "config audit clean"
  else
    bad "config audit found issues — run scripts/agent-loop-config-audit.sh"
    printf '%s\n' "$auditout" | grep -E '\[FAIL\]' | sed 's/^/      /'
  fi
else
  bad "scripts/agent-loop-config-audit.sh missing — cannot audit the agent configuration"
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "PREFLIGHT FAILED — the loop must NOT run until the [FAIL] items are fixed."
  exit 1
fi
echo "PREFLIGHT PASSED — gates verified; safe to run one supervised tick."
