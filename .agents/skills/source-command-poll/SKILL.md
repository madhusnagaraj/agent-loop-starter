---
name: "source-command-poll"
description: "One supervised tick of the loop — preflight, then dispatch the workers for queued issues/PRs. Wrap in your tool's loop."
---

# source-command-poll

Use this skill when the user asks to run the migrated source command `poll`.

## Command Template

# Poll — one supervised tick

A single pass of the loop, for running inside an interactive session wrapped in a repeating loop. It NEVER bypasses permission prompts and NEVER merges — it dispatches the State 1–3 workers and stops at the human merge gate.

## Precondition — run the preflight FIRST
```bash
bash scripts/agent-loop-preflight.sh || { echo "preflight failed — aborting tick"; exit 1; }
```
If it fails, STOP and report which gate is not yet real. The loop is only safe once the gates and the credential boundary verify (see the `agent-loop` skill). Run under the scoped loop identity.

## One tick
1. **Plan/implement queue** — `gh issue list --label ready` (for each without `plan-ready`, run `/plan`) and `--label approved` (for each without an open `agent/*` PR, run `/implement`). Skip CRITICAL-risk issues with a note.
2. **Validation queue** — `gh pr list --state open` filtered to `agent/*` heads without `self-review-passed`; run `/validate <pr#>` for each.
3. **Stop.** Do not merge. Emit a one-line summary per issue/PR handled.

## Safety
- Supervised + interactive only. Do not wrap this in an unattended job that skips permission prompts.
- Dev only; never merge; never push to the integration branch; never enable outbound side effects.
- This worker dispatches and reports; humans decide.
