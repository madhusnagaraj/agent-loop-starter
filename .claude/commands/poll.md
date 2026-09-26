---
description: One supervised tick of the loop — preflight, then dispatch the workers for queued issues/PRs. Wrap in your tool's loop.
---

# Poll — one supervised tick

A single pass of the loop, for running inside an interactive session wrapped in a repeating loop. It NEVER bypasses permission prompts and NEVER merges — it dispatches the State 1–3 workers and stops at the human merge gate.

## Precondition — run the preflight FIRST
```bash
bash scripts/agent-loop-preflight.sh || { echo "preflight failed — aborting tick"; exit 1; }
```
If it fails, STOP and report which gate is not yet real. The loop is only safe once the gates and the credential boundary verify (see the `agent-loop` skill). Run under the scoped loop identity.

## Gate provenance — verify the label, not just its presence
A label is a value an agent (or anyone) can set; only its **provenance** is trustworthy. The cloud guard checks this in-pipeline, but a local tick can otherwise race ahead on a gate label before the guard reverts it. So before acting on `ready`/`approved`, confirm the *latest* application of that label was done by a human on the allowlist. Source this helper and gate every dispatch through it:

```bash
# gate_ok <issue#> <ready|approved> — exit 0 only if the most recent `labeled` event for this
# label was applied by a non-Bot login on AGENT_GATE_MAINTAINERS. Fail-closed on any doubt.
gate_ok() {
  local num="$1" label="$2"
  local maint="${AGENT_GATE_MAINTAINERS:?set AGENT_GATE_MAINTAINERS in .env}"
  local ev login type
  ev=$(gh api "repos/$AGENT_REPO/issues/$num/timeline" \
        -H "Accept: application/vnd.github+json" --paginate \
        --jq "[.[] | select(.event==\"labeled\" and .label.name==\"$label\")] | last") || return 1
  [ -n "$ev" ] && [ "$ev" != "null" ] || { echo "#$num: no '$label' labeled-event found"; return 1; }
  login=$(printf '%s' "$ev" | jq -r '.actor.login // empty')
  type=$(printf '%s'  "$ev" | jq -r '.actor.type  // empty')
  [ "$type" != "Bot" ] || { echo "#$num: '$label' applied by Bot '$login' — gate not human"; return 1; }
  case ",${maint}," in
    *",${login},"*) return 0 ;;
    *) echo "#$num: '$label' applied by non-maintainer '$login'"; return 1 ;;
  esac
}
```

## One tick
1. **Plan queue** — `gh issue list --label ready`. For each issue without `plan-ready`: run `gate_ok <num> ready` first; if it fails, SKIP with the printed reason (do not plan on an unverified gate). Skip CRITICAL-risk issues with a note.
2. **Implement queue** — `gh issue list --label approved`. For each issue without an open `agent/*` PR: require BOTH `gate_ok <num> approved` AND that a plan was actually posted (`plan-ready` present on the issue) — never implement something that skipped planning. Skip on failure with the reason.
3. **Validation queue** — `gh pr list --state open` filtered to `agent/*` heads. A PR needs validation unless it carries `self-review-passed` **for its current head**. Treat the pass label as bound to a commit, not the PR: pull the latest evidence bundle and compare its recorded SHA to the live head —
   ```bash
   head=$(gh pr view "$pr" --json headRefOid --jq '.headRefOid')
   validated=$(gh pr view "$pr" --json comments \
     --jq '[.comments[].body | capture("Validated-HEAD: (?<s>[0-9a-f]{7,40})")?.s] | last // empty')
   [ "$head" = "$validated" ] && echo "skip — validated at $head" || echo "revalidate — head $head, evidence ${validated:-none}"
   ```
   Run `/validate <pr#>` for every PR that is not validated at its current head (no evidence, or stale evidence from an earlier commit).
4. **Stop.** Do not merge. Emit a one-line summary per issue/PR handled (include why any were skipped).

## Safety
- Supervised + interactive only. Do not wrap this in an unattended job that skips permission prompts.
- Dev only; never merge; never push to the integration branch; never enable outbound side effects.
- Provenance and SHA checks here are convenience, not the boundary — the real enforcement is `agent-gate-guard.yml` (reverts bad gate labels) and `agent-pr-resync.yml` (strips stale pass labels on new commits). This worker dispatches and reports; humans decide.
