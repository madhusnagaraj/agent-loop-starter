---
description: State 3 — review pair + dev validation of a PR, then post one evidence bundle. Never merges.
argument-hint: <pr-number>
---

# Validate (State 3)

Review and prove PR **$ARGUMENTS**, then post a single evidence bundle. Report-only: never merge, never push to shared branches, never deploy production.

## 0. Pin the head SHA
Evidence is only valid for the exact commit it was gathered against. Capture the head first and validate *that* commit:
```bash
SHA=$(gh pr view $ARGUMENTS --json headRefOid --jq '.headRefOid')
echo "validating $ARGUMENTS at $SHA"
```
If new commits land while you validate, your evidence is void — re-run against the new head. Never carry a verdict across a commit.

## 1. Self-review gate (parallel)
Dispatch both review agents on the PR diff in one go so they run concurrently:
- `code-reviewer` — correctness, logic, conventions, silent failures.
- `security-auditor` — authz, isolation, secrets, PII, input validation, migrations.

**Gate:** any CRITICAL (or unresolved HIGH security) ⇒ apply `self-review-needs-fixes`, post the findings, stop.

## 2. Dev validation (the harness — see the `dev-validation` skill)
Prove the change in a real, fenced environment:
- **Preflight:** confirm outbound side effects are off and data is synthetic before exercising anything.
- **Seed** the database with known synthetic data, **run the unit tests**, **drive the changed UI with Playwright** (assert content, expect 0 console errors, exercise the CRUD), **hit the API directly** to isolate the failing layer, and **compare what rendered against the seed**.
- Block on RED.

## 3. Evidence bundle
First re-read the head and confirm it still equals the pinned `$SHA`; if it moved, discard and restart at step 0. Then post ONE PR comment that **begins with the validated commit** so the evidence is bound to it:
```
Validated-HEAD: <SHA>
```
followed by four sections: **code review**, **security audit**, **dev validation** (deploy ✓ / routes ✓ / 0 console errors / CRUD ✓), and **static checks**. Then label:
```
gh pr edit $ARGUMENTS --add-label self-review-passed   # or self-review-needs-fixes
```
The label means "passed **at this commit**", not "passed forever". A push to the PR invalidates it: `agent-pr-resync.yml` strips the pass label on `synchronize`, and `/poll` re-validates any PR whose head differs from the last `Validated-HEAD`. Never `gh pr merge`. The bundle exists so a human merges with confidence.
