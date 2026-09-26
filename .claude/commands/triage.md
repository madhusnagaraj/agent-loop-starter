---
description: State 0 — read-only root-cause triage of a bug issue. Posts evidence; never self-promotes.
argument-hint: <issue-number>
---

# Triage (State 0)

Read-only root-cause analysis of issue **$ARGUMENTS**. You localize the bug and back it with evidence. You do **not** fix it, and you do **not** apply the `ready` label — you recommend; a human decides.

## Do
1. Read the issue: `gh issue view $ARGUMENTS --json title,body,comments`.
2. Reproduce the cause from the current code — read the relevant files, trace the path.
3. Confirm against real signal where possible: logs, and a **read-only** query against a non-production (or read-replica) database. Never write.
4. Post one comment with:
   - **Root cause** in one or two sentences.
   - **Where:** the offending `file:line`.
   - **Severity** and a short **class** (e.g. `logic`, `data`, `auth`, `perf`).
   - **Suggested fix direction** (not the code).
5. Apply labels: `gh issue edit $ARGUMENTS --add-label triaged`.

## Don't
- Don't write code, open a PR, or apply `ready`/`approved`.
- Don't touch production data or anything that sends a message.
- If you can't localize it with evidence, say so and what you'd need — don't guess confidently.
