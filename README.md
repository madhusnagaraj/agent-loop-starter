# Agent Loop Starter

A small, opinionated starter kit for building an **autonomous coding loop you can trust** — a pipeline of narrow, least-privilege agents connected by GitHub issue labels, gated by humans at the transitions that matter, with safety enforced *below* the agent.

Reference implementations are included for [Claude Code](https://docs.anthropic.com/claude-code) and [OpenAI Codex](https://developers.openai.com/codex/). The architecture itself is tool-neutral.

> **Status: an early, opinionated experiment.** This is a starting point to fork and adapt, not a finished framework. The autonomy is deliberately *not* "on" out of the box — you wire the human gates first. See [`docs/playbook.html`](docs/playbook.html) for the full reasoning.

---

## The idea in one picture

Don't build one big do-everything agent. Build an **assembly line**: narrow stations (agents), a conveyor belt (issue labels), human inspectors (gates), and fail-safes wired into the machinery (guardrails).

```
issue ─▶ triage ─▶ (human: ready) ─▶ plan ─▶ (human: approved) ─▶ implement ─▶ validate ─▶ (human: merge)
        read-only                     no code                      branch+PR     evidence
```

Each worker reads the current label, does one job, advances the label. Humans own the three transitions that matter. Read the full write-up in [`docs/playbook.html`](docs/playbook.html).

---

## What's in here

```
.claude/
  skills/
    agent-loop/SKILL.md        # the loop's own operating manual (states, labels, gates)
    dev-validation/SKILL.md    # how a worker proves its own change in a real environment
  agents/
    code-reviewer.md           # independent correctness review (read-only)
    security-auditor.md        # authz / secrets / input-validation review (read-only)
  commands/
    triage.md                  # State 0 — read-only root cause
    plan.md                    # State 1 — implementation plan
    implement.md               # State 2 — branch + tests + PR
    validate.md                # State 3 — review pair + dev validation → evidence bundle
    poll.md                    # the supervised /loop tick (self-gated by the preflight)
.agents/
  skills/                      # portable skill mirrors (kept in sync by the drift check)
.codex/
  agents/                      # Codex reviewer and security-auditor definitions
.github/workflows/             # required enforcement — runs outside the agent, never a prompt
  agent-gate-guard.yml         # reverts a gate label (ready/approved) applied by a non-human
  agent-pr-resync.yml          # strips a stale self-review-passed when the PR head moves
optional/cloud-triggers/       # OPTIONAL — fire /plan & /implement in CI on a label event...
  agent-plan.yml               #   ...you can ignore these and drive the loop locally via /poll
  agent-implement.yml          #   (each just invokes the .claude command; no logic of its own)
scripts/
  agent-loop-preflight.sh      # refuses to run the loop until the gates are real
  agent-loop-drift-check.sh    # fails if mirrored knowledge / gate-check logic drifts (preflight Gate 6)
  agent-loop-config-audit.sh   # static scan of the config: secrets / agent least-privilege / shell injection (preflight Gate 7)
  setup-labels.sh              # creates the label vocabulary
docs/
  playbook.html                # the full architecture + methodology
.env.example                   # the config knobs (copy to .env, fill in)
```

## Prompts, YAML, and settings — what's made of what

The loop's **brains are prompts**. `.claude/` is the canonical implementation; `.agents/` and `.codex/` expose the relevant pieces to other agent runtimes. `scripts/agent-loop-drift-check.sh` prevents portable skill mirrors from diverging. YAML is deliberately kept to the two things that *can't* be a prompt:

- **`agent-gate-guard.yml` is enforcement** — it reverts a gate label applied by a non-human. A guardrail you can prompt away isn't a guardrail, so this fires in CI, outside the agent. It's the one required workflow.
- **`optional/cloud-triggers/` is just plumbing** — an alternative to running `/poll` locally. Each file only *invokes* the matching `.claude` command, so the prompt lives in exactly one place.

The real safety floor isn't a file at all — it's **GitHub settings**: branch protection requiring a human review, and a dedicated bot identity for the worker. Prompts = brains, the guard = nerves, settings = bones.

---

## Quickstart — the weekend version

You don't build the whole line first. Build one station and the one gate that makes it real:

1. **Copy three things into your repo:** `.claude/` (the agents, commands, and skills), `scripts/`
   (the preflight and checks every later step runs), and `.github/workflows/` (the gate guard,
   the only required workflow, plus its PR-resync companion and CI checks). `.agents/`, `.codex/`,
   and `optional/` are optional; skip them until you need them, and the checks will skip them too.
   From a clone of this kit, with your repo at `../my-repo`:
   ```bash
   cp -R .claude scripts ../my-repo/ && mkdir -p ../my-repo/.github && cp -R .github/workflows ../my-repo/.github/
   ```
2. **Create the labels** (needs the [`gh` CLI](https://cli.github.com/)). The script reads `AGENT_REPO`:
   ```bash
   AGENT_REPO=<owner>/<repo> ./scripts/setup-labels.sh
   ```
3. **Turn on branch protection** requiring **1 approving review** on your integration branch. Use
   `PUT …/protection` (the `PATCH …/required_pull_request_reviews` endpoint only *updates* a branch
   that is already protected), and send JSON so the review count stays an integer:
   ```bash
   gh api -X PUT repos/<owner>/<repo>/branches/<branch>/protection --input - <<'JSON'
   {
     "required_status_checks": null,
     "enforce_admins": true,
     "required_pull_request_reviews": { "required_approving_review_count": 1 },
     "restrictions": null
   }
   JSON
   ```
   All four keys are required by the API; `null` disables the ones you are not using.
4. **Set the maintainer allowlist** (who may apply gate labels):
   ```bash
   gh api -X POST repos/<owner>/<repo>/actions/variables \
     -f name=AGENT_GATE_MAINTAINERS -f value='your-handle,teammate-handle'
   ```
5. **Run `/validate <pr#>` on your next real PR.** That's the loop in miniature: an independent reviewer you can't merge past.

Then add stations one at a time — the security auditor, the planner, the implementer — and let the labels carry work between them.

## Compatibility

| Surface | Included | Support level |
|---|---:|---|
| Claude Code | Commands, skills, and review agents | Reference implementation |
| OpenAI Codex | Portable skills and review agents | Supported building blocks; orchestration is host-driven |
| Local supervised loop | `/poll` command | Recommended default |
| GitHub Actions | Optional plan/implement triggers | Experimental; requires external gates first |

The label state machine and GitHub enforcement workflows are runtime-independent. Command invocation and agent-definition formats are the adapter layer.

---

## The two non-negotiables

This kit is mostly prompts. Prompts express *intent*; they can't be your safety boundary. Two things must live **below** the agent:

- **External gates.** Branch protection (a human review is required) + a dedicated bot identity for the worker (so the platform's own "author can't approve their own PR" rule guarantees a human reviewer) + `agent-gate-guard.yml` (reverts a gate label applied by anyone not on the allowlist) + `agent-pr-resync.yml` (strips a stale validation pass when the PR head moves, so evidence can't outlive its commit). The preflight goes past "a bot login is recorded": it checks the active token **is** that bot, the bot is **not** on the maintainer allowlist, and the bot **lacks** repo admin. An agent that can open its own gate has no gate.
- **A credential boundary.** The loop's identity should be *denied* write/admin credentials (e.g. an IAM permission boundary), so "read-only" is enforced, not requested. The preflight probes this — it tries to read a privileged secret and expects to be denied — and is **fail-closed**: if it can't run a probe that proves the deny (no `aws` CLI and no `AGENT_SECRET_PROBE_CMD` adapter), it refuses rather than passing on an unverified boundary.

`scripts/agent-loop-preflight.sh` is the executable form of the §13 activation checklist — seven gates covering the rows above, plus an operator attestation for the content controls it can't probe from outside your app (`AGENT_CONTENT_CONTROLS_ACK`), a structural-drift check (`agent-loop-drift-check.sh`), and a static config audit (`agent-loop-config-audit.sh` — no secrets in `.claude/`, no reviewer agent granted write tools, no untrusted input reaching a workflow shell). It **exits non-zero** until every gate is real, so the loop self-disables until it's safe.

---

## Label vocabulary

| Label | Applied by | Means / triggers |
|---|---|---|
| `bug` / `feature` | human | intake; routes to triage or straight to plan |
| `triaged` | triage worker | root cause posted (recommend-only) |
| `ready` | **human gate** | clear to plan → fires `agent-plan.yml` |
| `plan-ready` | plan worker | plan posted, awaiting approval |
| `approved` | **human gate** | clear to implement → fires `agent-implement.yml` |
| `self-review-passed` / `-needs-fixes` | validate worker | evidence bundle posted on the PR |
| *(merge)* | **human gate** | the only path into the main branch |

---

## Safety notes (read before running)

- **Run supervised.** Use the `/poll` command inside an interactive session wrapped in your tool's loop — not an unattended job that bypasses permission prompts.
- **Non-prod is synthetic-only.** Workers should test against seeded synthetic data, with outbound side effects (email/SMS/webhooks) disabled and credentials scoped to read.
- **Never auto-merge.** Every path ends at a human merge. The provided `agent-implement.yml` does not enable auto-merge by design.
- **This is a template.** Read every prompt and workflow before adopting it; tune the agent-mode constraints to your stack and risk tolerance.

## Limitations and threat model

This starter kit reduces accidental or over-broad agent authority; it does not make arbitrary agent execution safe by itself.

- GitHub branch protection, the dedicated bot identity, and the maintainer allowlist live outside this repository. The kit can probe them, but cannot install or guarantee them for you.
- The optional cloud triggers check the event actor only. They do not replace the full activation preflight.
- Credential isolation is environment-specific. You must configure either the AWS probe or `AGENT_SECRET_PROBE_CMD`, and the probe must run as the same identity as the loop.
- Prompt-level “read-only” instructions are not a security boundary. Enforce least privilege in the runtime, repository permissions, and secret store.
- Compromised maintainers, malicious third-party actions, dependency supply-chain attacks, and vulnerabilities in the underlying agent runtime remain outside this kit's boundary.
- The supplied validation workflow is a pattern, not proof of correctness. Adapt its tests and synthetic-data oracle to your application.

Start in a disposable repository with synthetic data. Run `bash scripts/agent-loop-preflight.sh` before enabling any trigger, and keep human approval and merge gates enabled.

## License

MIT — see [`LICENSE`](LICENSE). Use it, fork it, ship it.
