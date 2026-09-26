---
description: State 1 — produce an implementation plan for an approved-to-plan issue. No code.
argument-hint: <issue-number>
---

# Plan (State 1)

Produce an implementation plan for issue **$ARGUMENTS**. Planning only — write no code.

1. Read the issue and any triage comment (start from the triage's `file:line`, don't re-investigate from scratch).
2. Read the repo's `CLAUDE.md` / docs and the neighboring code for conventions.
3. Post the plan as a comment:
   - **Summary** (1–2 sentences)
   - **Affected areas / files** to create or modify
   - **Approach** (numbered steps)
   - **Tests to write**
   - **Risk:** LOW / MEDIUM / HIGH / CRITICAL
   - **Open questions for the human** (if any)
4. Apply `plan-ready`: `gh issue edit $ARGUMENTS --add-label plan-ready`.

Stop there. A human reviews the plan and applies `approved` — you never apply it yourself. Skip CRITICAL-risk work with a note that a human should implement it.
