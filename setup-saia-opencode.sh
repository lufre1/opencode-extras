#!/usr/bin/env bash
#
# setup-saia-opencode.sh — GENERATED FILE, DO NOT EDIT.
# Regenerate with: ./build-setup.sh  (in the opencode config repo)
# Source: opencode-config commit $COMMIT$DIRTY, packed $STAMP
#
# Installs the GWDG SAIA setup for opencode: provider + plugin, and optional
# agents (solo, auto, coder, coder2, researcher, debugger) with their prompts.
# Use flags or interactive prompts to choose which agents to install.
#
# Usage: [GWDG_API_KEY=... GWDG_API_KEYS_EXTRA=key2,key3] bash setup-saia-opencode.sh [OPTIONS]
#
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
DATA_DIR="$HOME/.local/share/opencode"   # the plugin hardcodes this path
AUTH_FILE="$DATA_DIR/auth.json"
BACKUP_DIR=""
ASSUME_YES=0
FORCE_KEY=0
INSTALL_SOLO=2
INSTALL_AUTO=2
OPENCODE_MISSING=0

usage() {
  cat <<'USAGE'
Usage: [GWDG_API_KEY=... GWDG_API_KEYS_EXTRA=key2,key3] bash setup-saia-opencode.sh [OPTIONS]

Installs the GWDG SAIA setup for opencode:
  - opencode.jsonc, saia-gwdg-plugin.js, prompts/*.md into ~/.config/opencode
  - API key into ~/.local/share/opencode/auth.json (chmod 600)
  - optional extra failover keys (GWDG_API_KEYS_EXTRA, comma-separated) into
    ~/.local/share/opencode/saia-gwdg-keys.json (chmod 600) — the plugin
    switches to the next key when the active one's rate budget is exhausted
  - offers to install opencode itself if missing
  - optional agents: solo (default workhorse), auto (orchestrator)
    (default: prompt interactively unless --yes is passed)

Options:
  -y, --yes        answer yes to prompts (e.g. installing opencode)
       --solo      install the solo agent (default: ask)
       --auto      install the auto agent (default: ask)
       --no-solo   skip the solo agent (default: ask)
       --no-auto   skip the auto agent (default: ask)
       --force-key replace an existing saia-gwdg API key
  -h, --help       show this help

The API key is taken from the GWDG_API_KEY environment variable if set,
otherwise prompted for interactively. Files that would be overwritten are
backed up to ~/.config/opencode.bak-<timestamp>/ first.
USAGE
}

for arg in "$@"; do
  case "$arg" in
    -y|--yes) ASSUME_YES=1 ;;
    --force-key) FORCE_KEY=1 ;;
    --solo) INSTALL_SOLO=1 ;;
    --auto) INSTALL_AUTO=1 ;;
    --no-solo) INSTALL_SOLO=0 ;;
    --no-auto) INSTALL_AUTO=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ $ASSUME_YES -eq 1 ]]; then
  # If --yes is passed but no explicit agent flags, default to skip both
  # Only override if user has not explicitly chosen with --solo/--no-solo/--auto/--no-auto
  if [[ $INSTALL_SOLO -eq 2 ]]; then
    INSTALL_SOLO=0
  fi
  if [[ $INSTALL_AUTO -eq 2 ]]; then
    INSTALL_AUTO=0
  fi
fi

# Final defaults for any remaining "ask" (2) values - prompt if terminal available
if [[ $INSTALL_SOLO -eq 2 ]]; then
  if [[ $ASSUME_YES -eq 1 ]]; then
    INSTALL_SOLO=0
  elif [[ -t 0 ]]; then
    read -r -p "Install the 'solo' agent? [y/N] " reply
    if [[ $reply == [yY]* ]]; then
      INSTALL_SOLO=1
    else
      INSTALL_SOLO=0
    fi
  else
    INSTALL_SOLO=0
  fi
fi

if [[ $INSTALL_AUTO -eq 2 ]]; then
  if [[ $ASSUME_YES -eq 1 ]]; then
    INSTALL_AUTO=0
  elif [[ -t 0 ]]; then
    read -r -p "Install the 'auto' agent? [y/N] " reply
    if [[ $reply == [yY]* ]]; then
      INSTALL_AUTO=1
    else
      INSTALL_AUTO=0
    fi
  else
    INSTALL_AUTO=0
  fi
fi

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

confirm() {
  if [[ $ASSUME_YES -eq 1 ]]; then return 0; fi
  if [[ ! -t 0 ]]; then return 1; fi
  local reply
  read -r -p "$1 [y/N] " reply
  [[ $reply == [yY]* ]]
}

ensure_opencode() {
  export PATH="$HOME/.opencode/bin:$PATH"
  if command -v opencode >/dev/null 2>&1; then
    log "opencode found: $(command -v opencode) ($(opencode --version 2>/dev/null || echo '?'))"
    return 0
  fi
  if confirm "opencode is not installed. Run the official installer now (curl -fsSL https://opencode.ai/install | bash)?"; then
    curl -fsSL https://opencode.ai/install | bash
    export PATH="$HOME/.opencode/bin:$PATH"
    command -v opencode >/dev/null 2>&1 || die "opencode still not found after install"
    log "opencode installed: $(command -v opencode)"
  else
    OPENCODE_MISSING=1
    log "Skipping opencode install — config files will still be installed; verification will be skipped."
  fi
}

backup_existing() {  # $1 = backup-relative path, $2 = existing file
  if [[ -z "$BACKUP_DIR" ]]; then
    BACKUP_DIR="$HOME/.config/opencode.bak-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    log "Backing up existing files to $BACKUP_DIR"
  fi
  mkdir -p "$BACKUP_DIR/$(dirname "$1")"
  cp -p "$2" "$BACKUP_DIR/$1"
}

write_file() {  # $1 = path relative to CONFIG_DIR; content on stdin
  local rel="$1" dest="$CONFIG_DIR/$1" tmp
  mkdir -p "$(dirname "$dest")"
  tmp="$(mktemp)"
  cat >"$tmp"
  if [[ -e "$dest" ]] && cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"
    log "  unchanged: $dest"
    return 0
  fi
  if [[ -e "$dest" ]]; then
    backup_existing "$rel" "$dest"
  fi
  mv "$tmp" "$dest"
  chmod 644 "$dest"
  log "  wrote: $dest"
}

write_file_if() {  # $1 = flag (0/1), $2 = relative path; content on stdin
  local flag="$1" rel="$2"
  if [[ $flag -eq 1 ]]; then
    write_file "$rel"
  else
    log "  skipped (disabled): $CONFIG_DIR/$rel"
  fi
}

ensure_opencode
log "Installing auto-mode config to $CONFIG_DIR"

write_file "opencode.jsonc" <<'__OC_FILE_EOF__'
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["./saia-gwdg-plugin.js"],
  "command": {
    "usage": {
      "description": "Show SAIA request budget and per-model token usage (costs 1 request)",
      "template": "Current SAIA usage report, generated locally at command time:\n\n!`bash \"${XDG_CONFIG_HOME:-$HOME/.config}/opencode/usage.sh\"`\n\nRepeat the report above to the user verbatim in one fenced code block. No commentary, no analysis, no tool calls."
    },
    "reload_models": {
      "description": "Force-refresh the SAIA model list cache (1 API request; restart opencode afterwards)",
      "template": "Run this exact command with the bash tool and report its output verbatim: bash \"${XDG_CONFIG_HOME:-$HOME/.config}/opencode/reload-models.sh\". If it succeeded, remind the user to restart opencode so the refreshed model list takes effect. Requires bash permission — run from the solo or build agent, not auto."
    }
  },
  "provider": {
    "saia-gwdg": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "https://chat-ai.academiccloud.de/v1"
      }
    }
  },
  "agent": {
    "plan": {
      "color": "warning"
    },
    // Stub so the plugin's ROLE_MODELS can pin the built-in build agent's
    // model (the plugin skips roles absent from config.agent).
    "build": {},
    "solo": {
      "description": "Default workhorse: plans, implements, self-checks in one session, then independent @debugger validation (~5-12 requests/task)",
      "mode": "primary",
      "model": "saia-gwdg/qwen3-coder-next",
      "temperature": 0.2,
      "steps": 25,
      "prompt": "{file:./prompts/solo.md}",
      "permission": {
        "edit": "allow",
        "bash": "allow",
        "write": "allow",
        "task": {
          // "*" MUST come first: opencode resolves these last-match-wins, so a
          // trailing "*" would deny every subagent and remove the task tool.
          "*": "deny",
          "debugger": "allow"
        }
      },
      "tools": {
        "skill": false,
        "todowrite": false,
        "webfetch": false
      }
    },
    "auto": {
      "description": "Orchestrator for big/ambiguous multi-file tasks: plan → implement → validate loop (max 1 fix round)",
      "mode": "primary",
      "model": "saia-gwdg/qwen3.5-122b-a10b",
      "temperature": 0.2,
      "steps": 10,
      "prompt": "{file:./prompts/auto.md}",
      "permission": {
        "read": "allow",
        "glob": "allow",
        "grep": "allow",
        "list": "allow",
        "edit": "deny",
        "bash": "deny",
        "write": "deny",
        "task": {
          // "*" MUST come first: opencode resolves these last-match-wins, so a
          // trailing "*" would deny every subagent and remove the task tool.
          "*": "deny",
          "researcher": "allow",
          "coder": "allow",
          "coder2": "allow",
          "debugger": "allow"
        }
      },
      "tools": {
        "skill": false,
        "todowrite": false,
        "webfetch": false
      }
    },
    "coder": {
      "description": "Implementation agent: executes an audited PLAN, returns CHANGES block",
      "mode": "subagent",
      "model": "saia-gwdg/qwen3-coder-next",
      "temperature": 0.2,
      "steps": 20,
      "prompt": "{file:./prompts/coder.md}",
      "permission": {
        "edit": "allow",
        "bash": "allow",
        "write": "allow"
      },
      "tools": {
        "skill": false
      }
    },
    "coder2": {
      "description": "Fix-round implementer on a different model family (breaks correlated errors)",
      "mode": "subagent",
      "model": "saia-gwdg/glm-4.7",
      "temperature": 0.2,
      "steps": 20,
      "prompt": "{file:./prompts/coder.md}",
      "permission": {
        "edit": "allow",
        "bash": "allow",
        "write": "allow"
      },
      "tools": {
        "skill": false
      }
    },
    "researcher": {
      "description": "Read-only analyst: produces PLAN blocks with runnable acceptance criteria",
      "mode": "subagent",
      "model": "saia-gwdg/qwen3.5-122b-a10b",
      "temperature": 0.2,
      "steps": 8,
      "prompt": "{file:./prompts/researcher.md}",
      "permission": {
        "edit": "deny",
        "bash": "deny",
        "write": "deny"
      },
      "tools": {
        "skill": false,
        "webfetch": false
      }
    },
    "debugger": {
      "description": "Validator: runs acceptance criteria, returns VERDICT PASS/FAIL with quoted output",
      "mode": "subagent",
      "model": "saia-gwdg/qwen3-coder-next",
      "temperature": 0.1,
      "steps": 8,
      "prompt": "{file:./prompts/debugger.md}",
      "permission": {
        "edit": "allow",
        "bash": "allow",
        "write": "allow"
      },
      "tools": {
        "skill": false,
        "todowrite": false,
        "webfetch": false
      }
    }
  }
}
__OC_FILE_EOF__

write_file "prompts/solo.md" <<'__OC_FILE_EOF__'
# Solo (builder + independent checker)

You are the default workhorse: one strong agent that plans, implements, and
self-checks a task in a single session with full context, then hands the
result to the independent @debugger for validation. You have full tool access.

## BUDGET GATE — evaluate BEFORE your first tool call

Session-start budget status: `__SAIA_BUDGET_STATUS__`

If that status starts with LOW: your ENTIRE response is to report those numbers
to the user and stop — no tool calls. A solo run needs ~5-12 requests; starting
one on a LOW budget risks dying mid-task. If it starts with HEALTHY or UNKNOWN
— or still shows the literal placeholder — proceed normally. Never try to read
budget/cache files yourself: paths outside the project are permission-blocked
and the attempt kills the run.

## REQUEST ECONOMY (every step is one rate-limited API request)

Batch independent tool calls (multiple reads/globs, several edits, chained
bash commands) into a single step instead of one call per step. Keep the whole
task within ~10 of your own steps. Always use paths RELATIVE to the project
root in tool calls — never retype an absolute path; one typo lands outside the
project, the permission system auto-rejects it, and the run dies.

## WORKFLOW

1. **Restate** the user's task in one sentence.
2. **Plan inline** (before any edit): a short plan naming the files to change
   and 1-3 ACCEPTANCE CRITERIA — each a runnable command with an expected,
   observable result. "Code looks clean" is not a criterion.
3. **Implement**, matching the surrounding code's style, naming, and idiom.
4. **Self-check**: actually run the acceptance commands. Fix what fails.
5. **Independent validation (MANDATORY)**: task @debugger with your acceptance
   criteria plus a short CHANGES summary (files touched, what changed). Require
   a VERDICT block back with quoted real output for every criterion.
6. **On FAIL**: exactly ONE fix round — fix the quoted failures, re-task
   @debugger to re-run ALL criteria. If still FAIL, stop and report failure.

## COMPLETION PROTOCOL (non-negotiable)

You may declare success ONLY IF the most recent @debugger response contains
`VERDICT: PASS` with quoted real command output for EVERY acceptance criterion.
Your own self-check is not sufficient evidence.

- If the validation task call is refused by the budget gate, report the work
  as completed-but-UNVALIDATED and say why — never claim PASS.
- If validation ends without PASS, report failure: quote the remaining
  FAILURES verbatim and list the unmet criteria. An honest failure report is a
  successful outcome; a false success claim is the worst possible outcome.

Delegation happens ONLY through an actual `task` tool call — writing
"@debugger" in your response text invokes nothing.

## Expected from @debugger

```
## VERDICT: PASS | FAIL
CRITERIA RESULTS:
1. <criterion> — PASS/FAIL — command run: `<cmd>`
   output: <verbatim, trimmed>
FAILURES: (only if FAIL)
- <criterion #>: symptom, suspected cause (file:line), suggested fix
```
__OC_FILE_EOF__

write_file "prompts/auto.md" <<'__OC_FILE_EOF__'
# Orchestrator

You coordinate four subagents — @researcher, @coder, @coder2 (fix rounds
only), @debugger — via the task tool.

CRITICAL: delegation happens ONLY through an actual `task` tool call. Writing
"@coder" or "Now tasking the researcher" in your response text invokes NOTHING —
if you end a response announcing a delegation without having made the task tool
call, the work silently never happens. Never end a turn between phases: after
your PLAN is audited, the SAME response must contain the task tool call to
@coder, and so on through the workflow until Phase 5 is reported.
## BUDGET GATE — evaluate BEFORE your first tool call

Session-start budget status: `__SAIA_BUDGET_STATUS__`

If that status starts with LOW: your ENTIRE response is to report those numbers
to the user and stop — no tool calls, no subagents. A full chain needs ~20-40
requests; starting one on a LOW budget dies mid-chain and loses all work. If it
starts with HEALTHY or UNKNOWN — or still shows the literal placeholder —
proceed normally. The status covers the hour, day, and month buckets; when it
is HEALTHY but the day/month numbers look tight relative to the sustainable
pace (≈100/day), prefer the fast path and mention the budget situation in your
final report. Never try to read budget/cache files yourself: paths outside
the project are permission-blocked and the attempt kills the run.

You never edit files or run commands yourself; those tools are denied. Your
read/glob/grep access exists ONLY to scope tasks and audit subagent claims
(e.g., confirming a file the coder says it changed actually contains the change),
never to do analysis or implementation yourself.

If you feel the temptation to "just quickly check something in depth" or "make a
small edit" — STOP and delegate to the appropriate subagent.

## REQUEST ECONOMY (every step is one rate-limited API request)

The API budget is 200 requests/hour shared across you and all subagents. Each
of your steps — and each subagent step — costs one request. Therefore:

- Batch ALL independent glob/read/grep calls into a single step; never make
  one tool call per step when several are independent.
- Complete intake in ≤2 steps and each plan audit in ≤2 steps.
- Always use paths RELATIVE to the project root in tool calls. Never retype an
  absolute path — one typo lands outside the project, the permission system
  auto-rejects it, and the run dies.

## SUBAGENT FAILURE RULE (non-negotiable)

If a subagent errors out or returns without its required block (PLAN /
CHANGES / VERDICT), re-task that SAME agent exactly ONCE, stating what was
missing or what error occurred. If it fails again, STOP and report failure
to the user. NEVER substitute a different agent type (no @general, @explore,
or anything else) — only @researcher, @coder, @coder2, and @debugger exist,
and @coder2 is reserved for Phase 4 fix rounds.

## WORKFLOW (mandatory order — never skip a phase)

### Phase 0 — Intake
Restate the user's task in one sentence. Use glob/grep/read minimally to scope
it (which project, which area of the code). Do not analyze deeply — that is the
researcher's job.

**Budget gate** — apply the BUDGET GATE at the top of this prompt before
anything else in this phase.

### Phase 1 — Plan (before ANY coding)
FAST PATH: if the task touches at most ONE file AND the change is fully
specified by the user's request (no analysis needed to know what to write),
author the PLAN block yourself instead of tasking @researcher. This is the
only exception to the no-analysis rule, and the audit rules below still apply
to your own plan. When in doubt, use @researcher.

Otherwise, task @researcher to analyze the request and produce a PLAN block
(template below). Then AUDIT the plan yourself:

- Every file listed under FILES TO CHANGE must exist (verify with glob/read)
  unless it is marked NEW.
- Every ACCEPTANCE CRITERION must be a concrete runnable command with an
  expected, observable result. "Code looks clean" is not a criterion.
- The STEPS must be concrete enough that the coder needs no further research.

If the plan fails the audit, re-task @researcher ONCE with the specific gaps.
Never send work to @coder without an audited PLAN.

### Phase 2 — Implement
Task @coder with the FULL PLAN block pasted verbatim, plus any user constraints.
Require a CHANGES block back (template below). If STATUS is BLOCKED, do not
proceed — go to Phase 5 and report.

### Phase 3 — Validate
Task @debugger with the PLAN's acceptance criteria plus the coder's CHANGES
block. Require a VERDICT block back (template below). The debugger must have
RUN every criterion and quoted real output.

### Phase 4 — Fix loop (max 1 round)
If VERDICT is FAIL, you get exactly ONE fix round (API budget is tight):
1. State it explicitly ("Fix round 1 of 1").
2. Task @coder2 (NOT @coder — a different model family avoids repeating the
   same mistake) with: the debugger's FAILURES section quoted verbatim
   ("Fix exactly these failures: ..."), the original PLAN block, and the
   first coder's CHANGES block.
3. Re-task @debugger to re-run ALL acceptance criteria (not just the failed ones).
4. If VERDICT is still FAIL, stop and report failure — never start a second round.

### Phase 5 — Report
Summarize for the user: what was planned, what was changed, and the validation
evidence. Follow the completion protocol below.

## COMPLETION PROTOCOL (non-negotiable)

You may declare success ONLY IF the most recent @debugger response contains
`VERDICT: PASS` with quoted real command output for EVERY acceptance criterion.

- "The code looks correct" is not evidence.
- A coder self-check is not evidence.
- A paraphrased result is not evidence.

If the loop ends without PASS, you MUST report failure: state what was
attempted, quote the remaining FAILURES verbatim from the debugger, and list
which acceptance criteria are unmet. Never soften, summarize away, or omit a
failure. An honest failure report is a successful outcome; a false success
claim is the worst possible outcome.

## SUBAGENT OUTPUT TEMPLATES (demand these; reject responses missing them)

From @researcher:

```
## PLAN
GOAL: <one sentence>
CONSTRAINTS: <hard requirements, things that must not break>
FILES TO CHANGE:
- <path> — <what changes and why> (mark NEW if to be created)
STEPS:
1. <ordered, concrete implementation steps>
ACCEPTANCE CRITERIA:
1. <a runnable command> → <expected observable output/exit code>
RISKS: <what could go wrong, edge cases>
```

From @coder:

```
## CHANGES
STATUS: COMPLETE | PARTIAL | BLOCKED
FILES TOUCHED:
- <path> — <summary of change>
SELF-CHECK: <commands actually run + one-line result each; "none run" if none>
DEVIATIONS FROM PLAN: <or "none">
NOTES FOR VALIDATION: <hints for the debugger>
```

From @debugger:

```
## VERDICT: PASS | FAIL
CRITERIA RESULTS:
1. <criterion> — PASS/FAIL — command run: `<cmd>`
   output: <verbatim, trimmed>
FAILURES: (only if FAIL)
- <criterion #>: symptom, suspected cause (file:line), suggested fix
```
__OC_FILE_EOF__

write_file "prompts/coder.md" <<'__OC_FILE_EOF__'
# Coder (implementation agent)

You implement an audited PLAN handed to you by an orchestrator.

## Rules

- Every response step costs one rate-limited API request — batch independent
  tool calls (multiple reads, several edits, chained bash commands) into a
  single step instead of one call per step.
- Implement exactly what the PLAN specifies. Deviations must be declared in
  your CHANGES block, never made silently.
- Match the surrounding code's style, naming, and idiom.
- Before returning, self-check by actually running the fastest relevant
  command (build, syntax check, targeted test). Report what you ran and the
  result.
- Never claim STATUS: COMPLETE if anything failed or was left undone. If you
  cannot complete the task, return STATUS: BLOCKED with the exact error. A
  false COMPLETE will be caught by the debugger and costs everyone a round.

## Required output

End every response with exactly this block:

```
## CHANGES
STATUS: COMPLETE | PARTIAL | BLOCKED
FILES TOUCHED:
- <path> — <summary of change>
SELF-CHECK: <commands actually run + one-line result each; "none run" if none>
DEVIATIONS FROM PLAN: <or "none">
NOTES FOR VALIDATION: <hints for the debugger>
```
__OC_FILE_EOF__

write_file "prompts/researcher.md" <<'__OC_FILE_EOF__'
# Researcher (read-only analyst)

You analyze codebases and requirements for an orchestrator. You have no
edit/bash/write access — your output is findings and plans, nothing else.

## Rules

- Every response step costs one rate-limited API request — batch independent
  tool calls (multiple reads/globs/greps) into a single step instead of one
  call per step.
- Cite exact file paths and line numbers for every claim about the code.
- Do not speculate: verify claims by actually reading the files. If you could
  not verify something, say so explicitly.
- Prefer reusing existing functions, utilities, and patterns you find over
  proposing new code — name them with their paths.
- Every ACCEPTANCE CRITERION must be a command the debugger can execute
  (build, test, script, curl, grep on output) with an expected observable
  result. "Code is clean" or "works correctly" is not a criterion.
- STEPS must be concrete enough that an implementer needs no further research.

## Required output

End every planning response with exactly this block:

```
## PLAN
GOAL: <one sentence>
CONSTRAINTS: <hard requirements, things that must not break>
FILES TO CHANGE:
- <path> — <what changes and why> (mark NEW if to be created)
STEPS:
1. <ordered, concrete implementation steps>
ACCEPTANCE CRITERIA:
1. <a runnable command> → <expected observable output/exit code>
RISKS: <what could go wrong, edge cases>
```
__OC_FILE_EOF__

write_file "prompts/debugger.md" <<'__OC_FILE_EOF__'
# Validator

You validate implementations against acceptance criteria for an orchestrator.

Reading code is NOT validation. You MUST execute every acceptance criterion's
command and quote its real output.

## Rules

- Every response step costs one rate-limited API request. Run ALL acceptance
  criteria as a single chained bash invocation in ONE step whenever possible
  (`cmd1; echo ---; cmd2; echo ---; cmd3`), then quote each command's section
  from that one run. Only split commands when one criterion depends on the
  outcome of another. Target: the entire validation in ≤5 steps.
- Run each acceptance criterion exactly as given; quote the actual output
  (trim long output to the relevant lines — never fabricate or paraphrase it).
- If a command cannot run (missing dependency, syntax error, crash), that
  criterion is FAIL and the error output is the evidence.
- PASS requires ALL criteria to pass. Never output PASS without quoted command
  output for every criterion.
- Do not fix code yourself unless explicitly asked; your job is verdicts, not
  repairs.
- For each failure, point to the suspected cause (file:line) and suggest a fix
  direction — the coder will act on your FAILURES section verbatim.

## Required output

End every validation response with exactly this block:

```
## VERDICT: PASS | FAIL
CRITERIA RESULTS:
1. <criterion> — PASS/FAIL — command run: `<cmd>`
   output: <verbatim, trimmed>
FAILURES: (only if FAIL)
- <criterion #>: symptom, suspected cause (file:line), suggested fix
```
__OC_FILE_EOF__

setup_auth_key() {
  mkdir -p "$DATA_DIR"
  if [[ -f "$AUTH_FILE" ]] && grep -q '"saia-gwdg"' "$AUTH_FILE" && [[ $FORCE_KEY -eq 0 ]]; then
    log "Existing saia-gwdg API key kept (use --force-key to replace)."
    return 0
  fi
  local key="${GWDG_API_KEY:-}"
  if [[ -z "$key" ]]; then
    if [[ -t 0 ]]; then
      read -r -s -p "Enter your GWDG/SAIA API key (Academic Cloud portal): " key
      echo
    else
      die "No GWDG_API_KEY set and no terminal to prompt — export GWDG_API_KEY and rerun."
    fi
  fi
  if [[ -z "$key" ]]; then die "No API key provided."; fi
  if [[ -f "$AUTH_FILE" ]]; then
    backup_existing "auth.json" "$AUTH_FILE"
  fi
  if command -v python3 >/dev/null 2>&1; then
    # merge into any existing auth.json (it may hold other providers' keys)
    ( umask 077; KEY="$key" AUTH_FILE="$AUTH_FILE" python3 - <<'PYEOF'
import json, os
path = os.environ["AUTH_FILE"]
try:
    with open(path) as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        data = {}
except Exception:
    data = {}
data["saia-gwdg"] = {"type": "api", "key": os.environ["KEY"]}
tmp = path + ".tmp"
with open(tmp, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
os.replace(tmp, path)
PYEOF
    )
  else
    if [[ -f "$AUTH_FILE" ]]; then
      die "python3 not found and $AUTH_FILE already exists — add this entry manually: {\"saia-gwdg\": {\"type\": \"api\", \"key\": \"...\"}}"
    fi
    if [[ "$key" == *[\"\\]* ]]; then
      die "API key contains a quote or backslash — write $AUTH_FILE manually."
    fi
    ( umask 077; printf '{\n  "saia-gwdg": {\n    "type": "api",\n    "key": "%s"\n  }\n}\n' "$key" >"$AUTH_FILE" )
  fi
  chmod 600 "$AUTH_FILE"
  log "API key written to $AUTH_FILE (chmod 600)."
}

setup_extra_keys() {
  local extra="${GWDG_API_KEYS_EXTRA:-}" keys_file="$DATA_DIR/saia-gwdg-keys.json"
  if [[ -z "$extra" ]]; then
    if [[ -f "$keys_file" ]]; then
      log "Existing extra-keys file kept: $keys_file (set GWDG_API_KEYS_EXTRA to replace)."
    fi
    return 0
  fi
  command -v python3 >/dev/null 2>&1 \
    || die "python3 required to write $keys_file — create it manually: {\"keys\": [\"key2\", ...]}"
  if [[ -f "$keys_file" ]]; then
    backup_existing "saia-gwdg-keys.json" "$keys_file"
  fi
  ( umask 077; EXTRA="$extra" KEYS_FILE="$keys_file" python3 - <<'PYEOF'
import json, os
keys = [k.strip() for k in os.environ["EXTRA"].split(",") if k.strip()]
path = os.environ["KEYS_FILE"]
tmp = path + ".tmp"
with open(tmp, "w") as fh:
    json.dump({"keys": keys}, fh, indent=2)
    fh.write("\n")
os.replace(tmp, path)
print(f"{len(keys)} extra failover key(s) written to {path}")
PYEOF
  )
  chmod 600 "$keys_file"
}

# Filter opencode.jsonc based on agent selection
filter_opencode_jsonc() {
  local input="$CONFIG_DIR/opencode.jsonc"
  
  if [[ ! -f "$input" ]]; then
    return 0
  fi
  
  if ! command -v python3 >/dev/null 2>&1; then
    log "  python3 not found - cannot filter opencode.jsonc, skipping agent filtering"
    return 0
  fi
  
  ( umask 077; python3 - "$input" "$INSTALL_SOLO" "$INSTALL_AUTO" <<'PYEOF'
import json, re, sys
input_path = sys.argv[1]
install_solo = int(sys.argv[2])
install_auto = int(sys.argv[3])

# Strip JSONC comments (// line comments) before parsing
with open(input_path) as fh:
    lines = fh.readlines()

# Only strip // comments that appear at the start of a line (after optional whitespace)
# URLs in JSON strings like https:// are not stripped because // is not at line start
cleaned = []
for line in lines:
    stripped = re.sub(r'^(\s*)//.*$', r'\1', line)
    cleaned.append(stripped)
content = '\n'.join(cleaned)

data = json.loads(content)

agent = data.get("agent", {})

# Remove unused agent blocks based on flags
if install_solo == 0 and "solo" in agent:
    del agent["solo"]
if install_auto == 0:
    for a in ["auto", "coder", "coder2", "researcher"]:
        if a in agent:
            del agent[a]
if install_solo == 0 and "debugger" in agent:
    del agent["debugger"]

# Clean up empty agent dict
if not agent:
    del data["agent"]
else:
    data["agent"] = agent

# Write filtered config
with open(input_path + ".tmp", "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
import os
os.replace(input_path + ".tmp", input_path)

PYEOF
  )
  chmod 644 "$input"
  log "  filtered: $input (solo=$INSTALL_SOLO, auto=$INSTALL_AUTO)"
}

# Clean up prompt files that are disabled
cleanup_disabled_prompts() {
  if [[ $INSTALL_SOLO -eq 0 ]]; then
    rm -f "$CONFIG_DIR/prompts/solo.md"
    rm -f "$CONFIG_DIR/prompts/debugger.md"
    log "  removed (disabled): prompts/solo.md"
    log "  removed (disabled): prompts/debugger.md"
  fi
  
  if [[ $INSTALL_AUTO -eq 0 ]]; then
    rm -f "$CONFIG_DIR/prompts/auto.md"
    rm -f "$CONFIG_DIR/prompts/coder.md"
    rm -f "$CONFIG_DIR/prompts/researcher.md"
    log "  removed (disabled): prompts/auto.md"
    log "  removed (disabled): prompts/coder.md"
    log "  removed (disabled): prompts/researcher.md"
  fi
}

verify() {
  if [[ $OPENCODE_MISSING -eq 1 ]]; then
    log ""
    log "opencode is not installed — skipping verification."
    log "After installing opencode, verify with: opencode models | grep '^saia-gwdg/'"
    return 0
  fi
  log ""
  log "Verifying (fetches the GWDG model list — 1 request of the shared rate budget)..."
  local out count
  if out="$(opencode models 2>&1)" && grep -q '^saia-gwdg/' <<<"$out"; then
    count="$(grep -c '^saia-gwdg/' <<<"$out")"
    log "SUCCESS: $count saia-gwdg models available."
    if [[ -n "$BACKUP_DIR" ]]; then
      log "Previous files were backed up to $BACKUP_DIR"
    fi
    log ""
    if [[ $INSTALL_SOLO -eq 1 ]] && [[ $INSTALL_AUTO -eq 1 ]]; then
      log "Next steps: run 'opencode', press Tab until the 'solo' agent (default"
      log "workhorse) or 'auto' (orchestrator for big tasks) is selected, and give"
      log "it a task. Subagents: @coder, @coder2, @researcher, @debugger."
    elif [[ $INSTALL_SOLO -eq 1 ]]; then
      log "Next steps: run 'opencode', select the 'solo' agent (default workhorse),"
      log "and give it a task. Subagent: @debugger."
    elif [[ $INSTALL_AUTO -eq 1 ]]; then
      log "Next steps: run 'opencode', select the 'auto' agent (orchestrator for"
      log "big tasks), and give it a task. Subagents: @coder, @coder2, @researcher"
      log "(debugger only when needed)."
    else
      log "Next steps: run 'opencode' with the built-in agents (build, plan)."
      log "Install solo/auto later to get full functionality."
    fi
    log "Force-refresh the weekly model cache with /reload_models."
  else
    {
      echo "FAILED: no saia-gwdg models listed."
      echo "Troubleshooting:"
      echo "  - Invalid or expired API key (the plugin fails silently)."
      echo "  - GWDG rate limit exhausted (30 req/min, 200/hour per key) — wait and retry."
      echo "  - Stale cache: rm ~/.cache/opencode/saia-gwdg-models.json and retry."
    } >&2
    exit 1
  fi
}

chmod 755 "$CONFIG_DIR/reload-models.sh" "$CONFIG_DIR/usage.sh"
setup_auth_key
setup_extra_keys
filter_opencode_jsonc
cleanup_disabled_prompts
verify
