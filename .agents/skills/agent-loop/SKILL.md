---
name: agent-loop
description: The operating manual for this autonomous coding loop — the states, the label state machine, the human gates, and the rule that gates are enforced outside the agent. Load when triaging, planning, implementing, validating, or polling, or when reasoning about how the loop is wired.
---

# The agent loop

A pipeline of narrow, least-privilege workers connected by GitHub issue labels, with a human gate at the transitions that matter. The issue is the bus; **labels are the state**. Not one big agent — an assembly line of small ones.

## States
| State | Worker (command) | Does | Writes | Advances by |
|---|---|---|---|---|
| 0 Triage | `/triage` | read-only root cause; posts evidence | comment | human applies `ready` |
| 1 Plan | `/plan` | implementation plan | comment | human applies `approved` |
| 2 Implement | `/implement` | branch + tests + PR | code on a branch | opens PR |
| 3 Validate | `/validate` | review pair + dev validation → evidence bundle | comment + label | human merges |

Bugs enter at triage; features skip it and start at plan. Both are just GitHub issues.

## Label lifecycle
`triaged → (human) ready → plan-ready → (human) approved → PR open → self-review-passed → (human) merge`

A worker reads the label that precedes it and advances to the next. The **gate labels (`ready`, `approved`) and the merge are HUMAN-applied** — a worker must never apply them, and must never wake the *next* worker on its own completion (e.g. `plan-ready` must not trigger implement; only the human `approved` does).

## The non-negotiable rule
Gates are enforced **outside the agent**: branch protection requires a human review; the worker runs as a dedicated bot identity (so the author can't be the approver); `agent-gate-guard.yml` reverts any gate label applied by a non-human. An agent that can open its own gate has no gate.

## Two runtimes, one vocabulary
- **Cloud:** GitHub Actions fire on the `labeled` event (`ready` → `agent-plan.yml`, `approved` → `agent-implement.yml`).
- **Local:** the `/poll` command scans the same labels in a supervised session.
The labels are the contract; where a worker runs is an implementation detail.

## Safety spine
- **Content controls** stop wrong actions: a fail-closed fence on outbound side effects in non-prod; synthetic-only data.
- **Boundary controls** stop excess authority: the loop identity is *denied* write/admin credentials.
- `scripts/agent-loop-preflight.sh` verifies all of the above and refuses to run until they hold.
