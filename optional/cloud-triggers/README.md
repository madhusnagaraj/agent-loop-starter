# Optional: cloud triggers

**You don't need these to run the loop.** The default path is prompt-only: drive the loop locally with the `/poll` command (and the `/plan`, `/implement`, `/validate` commands), in a supervised session.

These two workflows are an *alternative* runtime — they fire the same commands in the cloud on a GitHub label event instead of from your machine. They contain no logic of their own; each just invokes the committed slash command (`.claude/commands/plan.md` / `implement.md`), which stays the single source of truth.

## When to add them
- You want plan/implement to kick off automatically when a maintainer applies `ready` / `approved`, without anyone running a local session.

## How to activate
0. **Confirm `bash scripts/agent-loop-preflight.sh` passes in your environment first.** These triggers only run the per-event gate-check (the actor allowlist) — they do **not** re-run the full activation preflight. The merge gate, bot identity, credential boundary, content-control attestation, and drift check must already be green before you turn on cloud firing; otherwise you'd be event-triggering a loop whose boundary was never verified.
1. Copy the file(s) into `.github/workflows/` in your repo.
2. Add the repo secret `CLAUDE_CODE_OAUTH_TOKEN`.
3. Set the repo variable `AGENT_GATE_MAINTAINERS` (comma-separated human logins).
4. (Recommended) set `AGENT_BASE_BRANCH` if your integration branch isn't `main`.

## What stays required regardless
The workflows that are **not** optional are the *enforcement* ones, because enforcement can't be a prompt:
- `.github/workflows/agent-gate-guard.yml` — reverts a gate label (`ready` / `approved`) applied by a non-human.
- `.github/workflows/agent-pr-resync.yml` — strips a stale `self-review-passed` when the PR head moves, so State-3 evidence can't outlive the commit it was gathered against.

Together with branch protection (a repo setting) and a dedicated bot identity, that's the safety floor. These cloud triggers are just convenience on top.

> Note: these two trigger files repeat one small gate-check shell block. That duplication is intentional (each must gate independently) but kept honest by `scripts/agent-loop-drift-check.sh`, which fails if the shared logic drifts between them.
