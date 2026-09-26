---
description: State 2 — implement an approved plan on a branch, with tests, and open a PR. Never merges.
argument-hint: <issue-number>
---

# Implement (State 2)

Implement the approved plan for issue **$ARGUMENTS** on a feature branch and open a PR. You never merge and never enable auto-merge — you hand off to validation (State 3) and a human merges.

1. Confirm no open PR already exists for this issue.
2. Branch from the integration branch: `git checkout <base> && git pull && git checkout -b agent/$ARGUMENTS`.
3. Implement to the approved plan; incorporate any human feedback comments.
4. **Write tests for all new behavior.**
5. Run the repo's quick checks (type-check / lint / unit tests) and fix failures.
6. Commit, push the branch, open a PR that references issue #$ARGUMENTS.
7. Comment the PR link on the issue. **Stop** — do not merge.

Constraints (tune to your stack and risk tolerance):
- Don't modify CI/CD workflows, secrets, or auth configuration.
- Don't modify code that sends real outbound messages (email/SMS/webhooks).
- Don't run deploys or touch production data.
- Branch only; never push to the integration branch directly; never merge your own PR.
