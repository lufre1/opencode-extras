#!/usr/bin/env bash
#
# install-auto-mode.sh — GENERATED FILE, DO NOT EDIT.
# Regenerate with: ./build-installer.sh  (in the opencode config repo)
# Source: opencode-config commit 1e9489a, packed 2026-07-10T09:38:06Z
#
# Installs the GWDG SAIA auto-mode setup for opencode: provider + plugin,
# agents (auto, coder, researcher, debugger) with their prompts, and the
# API key in ~/.local/share/opencode/auth.json.
#
# Usage: [GWDG_API_KEY=...] bash install-auto-mode.sh [--yes] [--force-key]
#
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
DATA_DIR="$HOME/.local/share/opencode"   # the plugin hardcodes this path
AUTH_FILE="$DATA_DIR/auth.json"
BACKUP_DIR=""
ASSUME_YES=0
FORCE_KEY=0
OPENCODE_MISSING=0

usage() {
  cat <<'USAGE'
Usage: [GWDG_API_KEY=...] bash install-auto-mode.sh [OPTIONS]

Installs the GWDG SAIA auto-mode setup for opencode:
  - opencode.jsonc, saia-gwdg-plugin.js, prompts/*.md into ~/.config/opencode
  - API key into ~/.local/share/opencode/auth.json (chmod 600)
  - offers to install opencode itself if missing

Options:
  -y, --yes        answer yes to prompts (e.g. installing opencode)
      --force-key  replace an existing saia-gwdg API key
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
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

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

ensure_opencode
log "Installing auto-mode config to $CONFIG_DIR"

write_file opencode.jsonc <<'__OC_FILE_EOF__'
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["./saia-gwdg-plugin.js"],
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
    "auto": {
      "description": "Orchestrator: plan → implement → validate loop (max 3 fix rounds)",
      "mode": "primary",
      "model": "saia-gwdg/qwen3.5-122b-a10b",
      "temperature": 0.2,
      "steps": 12,
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
          "researcher": "allow",
          "coder": "allow",
          "debugger": "allow"
        }
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
      }
    },
    "debugger": {
      "description": "Validator: runs acceptance criteria, returns VERDICT PASS/FAIL with quoted output",
      "mode": "subagent",
      "model": "saia-gwdg/devstral-2-123b-instruct-2512",
      "temperature": 0.1,
      "steps": 12,
      "prompt": "{file:./prompts/debugger.md}",
      "permission": {
        "edit": "allow",
        "bash": "allow",
        "write": "allow"
      }
    }
  }
}
__OC_FILE_EOF__

write_file saia-gwdg-plugin.js <<'__OC_FILE_EOF__'
import { readFileSync, writeFileSync, mkdirSync, appendFileSync } from "fs";
import { homedir } from "os";
import { join, dirname } from "path";

// The model list is fetched fresh from GWDG at every opencode launch (one
// /v1/models request against the shared SAIA bucket: 30/min, 200/hour,
// 1000/day, 3000/month). The cache file is only a fallback: on fetch failure
// (offline, 429, budget abort) it is used instead of loading no models.
const CACHE_PATH = join(homedir(), ".cache/opencode/saia-gwdg-models.json");

// ---------------------------------------------------------------------------
// Request pacer: wraps globalThis.fetch for chat-ai.academiccloud.de only.
// - spaces request starts >= 2100ms apart so the 30/min limit can't trip
// - stops with a clear error when the hour/day bucket is nearly empty,
//   instead of letting opencode retry-spin 429s into a drained bucket
// - on 429, waits for the advertised reset once and retries; a second 429
//   throws
// Patching global fetch (not provider options.fetch) because opencode may
// not pass function-valued config through to the SDK.
// ---------------------------------------------------------------------------
const SAIA_HOST = "chat-ai.academiccloud.de";
const MIN_INTERVAL_MS = 2100;
const HOUR_FLOOR = 5;
const DAY_FLOOR = 10;
const PACER_LOG = join(homedir(), ".cache/opencode/saia-gwdg-pacer.log");

function installPacer() {
  if (globalThis.__saiaPacerInstalled) return;
  globalThis.__saiaPacerInstalled = true;

  const realFetch = globalThis.fetch.bind(globalThis);
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  let queue = Promise.resolve(); // serializes SAIA requests
  let lastStart = 0;
  let remaining = { minute: null, hour: null, day: null };

  const readBuckets = (resp) => {
    for (const b of ["minute", "hour", "day"]) {
      const v = resp.headers.get(`x-ratelimit-remaining-${b}`);
      if (v !== null) remaining[b] = Number(v);
    }
  };

  const debugLog = (line) => {
    if (process.env.SAIA_PACER_DEBUG !== "1") return;
    try {
      mkdirSync(dirname(PACER_LOG), { recursive: true });
      appendFileSync(PACER_LOG, `${new Date().toISOString()} ${line}\n`);
    } catch {}
  };

  globalThis.fetch = (input, init) => {
    let url;
    try {
      url = new URL(typeof input === "string" ? input : input.url ?? String(input));
    } catch {
      return realFetch(input, init);
    }
    if (url.hostname !== SAIA_HOST) return realFetch(input, init);

    const run = queue.then(async () => {
      if (remaining.hour !== null && remaining.hour <= HOUR_FLOOR) {
        throw new Error(
          `SAIA hourly budget nearly exhausted (${remaining.hour} requests left this hour) — ` +
            `aborting instead of retry-spinning. Wait for the hour to reset.`
        );
      }
      if (remaining.day !== null && remaining.day <= DAY_FLOOR) {
        throw new Error(
          `SAIA daily budget nearly exhausted (${remaining.day} requests left today) — aborting.`
        );
      }

      const wait = lastStart + MIN_INTERVAL_MS - Date.now();
      if (wait > 0) await sleep(wait);
      lastStart = Date.now();

      let resp = await realFetch(input, init);
      readBuckets(resp);
      if (resp.status === 429) {
        const reset = Number(resp.headers.get("ratelimit-reset")) || 60;
        debugLog(`429 ${url.pathname} — waiting ${Math.min(reset, 65)}s before one retry`);
        await sleep(Math.min(reset, 65) * 1000);
        lastStart = Date.now();
        resp = await realFetch(input, init);
        readBuckets(resp);
        if (resp.status === 429) {
          throw new Error(
            `SAIA rate limit still exceeded after waiting (remaining: ` +
              `${remaining.minute}/min, ${remaining.hour}/hour, ${remaining.day}/day) — aborting.`
          );
        }
      }
      debugLog(
        `${resp.status} ${url.pathname} remaining=${remaining.minute}/min ${remaining.hour}/hour ${remaining.day}/day`
      );
      return resp;
    });

    // keep the chain alive even when a request fails
    queue = run.catch(() => {});
    return run;
  };
}

// Preferred model per agent role, best first. The plugin picks the first entry
// that SAIA currently reports as `ready`; if none are ready it falls back to any
// available model so auto mode keeps working. Edit THIS to change auto-mode models.
const ROLE_MODELS = {
  auto:       ["qwen3.5-122b-a10b", "qwen3-coder-next"],
  coder:      ["qwen3-coder-next", "devstral-2-123b-instruct-2512"],
  researcher: ["qwen3.5-122b-a10b", "qwen3-coder-next"],
  debugger:   ["devstral-2-123b-instruct-2512", "qwen3-coder-next"],
};

export const server = async (_input) => {
  return {
    config: async (config) => {
      installPacer();

      let key;
      try {
        const authPath = join(homedir(), ".local/share/opencode/auth.json");
        const auth = JSON.parse(readFileSync(authPath, "utf-8"));
        key = auth["saia-gwdg"]?.key;
      } catch {
        return;
      }

      if (!key) return;

      let cached;
      try {
        cached = JSON.parse(readFileSync(CACHE_PATH, "utf-8"));
      } catch {}

      let models;
      try {
        const resp = await fetch("https://chat-ai.academiccloud.de/v1/models", {
          headers: { Authorization: `Bearer ${key}` },
        });
        if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
        const json = await resp.json();
        models = json.data;
        try {
          mkdirSync(dirname(CACHE_PATH), { recursive: true });
          writeFileSync(CACHE_PATH, JSON.stringify({ fetchedAt: Date.now(), models }));
        } catch {}
      } catch {
        models = cached?.models; // stale cache beats no models
      }

      if (!models) return;

      if (!config.provider) config.provider = {};
      if (!config.provider["saia-gwdg"]) {
        config.provider["saia-gwdg"] = {
          npm: "@ai-sdk/openai-compatible",
          options: { baseURL: "https://chat-ai.academiccloud.de/v1" },
        };
      }

      config.provider["saia-gwdg"].models = {};
      for (const m of models) {
        if (m.status !== "ready") continue;
        config.provider["saia-gwdg"].models[m.id] = {
          name: m.name,
          attachment: m.input?.some((t) => ["image", "audio", "video"].includes(t)),
          reasoning: m.output?.includes("thought"),
        };
      }

      // Resolve each agent's model from ROLE_MODELS against the live list:
      // first preference that is ready wins, otherwise any ready model.
      const ready = new Set(Object.keys(config.provider["saia-gwdg"].models));
      const anyReady = [...ready][0];

      if (config.agent) {
        const providerModels = config.provider["saia-gwdg"].models;
        for (const [role, prefs] of Object.entries(ROLE_MODELS)) {
          const agent = config.agent[role];
          if (!agent) continue;
          let pick = prefs.find((id) => ready.has(id));
          if (role === "auto") {
            // the orchestrator benefits from thinking before delegating
            pick =
              prefs.find((id) => ready.has(id) && providerModels[id]?.reasoning) ??
              pick ??
              [...ready].find((id) => providerModels[id]?.reasoning);
          }
          pick = pick ?? anyReady;
          if (pick) agent.model = `saia-gwdg/${pick}`;
        }
      }
    },
  };
};
__OC_FILE_EOF__

write_file prompts/auto.md <<'__OC_FILE_EOF__'
# Orchestrator

You coordinate three subagents — @researcher, @coder, @debugger — via the task tool.
You never edit files or run commands yourself; those tools are denied. Your
read/glob/grep access exists ONLY to scope tasks and audit subagent claims
(e.g., confirming a file the coder says it changed actually contains the change),
never to do analysis or implementation yourself.

If you feel the temptation to "just quickly check something in depth" or "make a
small edit" — STOP and delegate to the appropriate subagent.

## WORKFLOW (mandatory order — never skip a phase)

### Phase 0 — Intake
Restate the user's task in one sentence. Use glob/grep/read minimally to scope
it (which project, which area of the code). Do not analyze deeply — that is the
researcher's job.

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
2. Re-task @coder with the debugger's FAILURES section quoted verbatim:
   "Fix exactly these failures: ..."
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

write_file prompts/coder.md <<'__OC_FILE_EOF__'
# Coder (implementation agent)

You implement an audited PLAN handed to you by an orchestrator.

## Rules

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

write_file prompts/debugger.md <<'__OC_FILE_EOF__'
# Validator

You validate implementations against acceptance criteria for an orchestrator.

Reading code is NOT validation. You MUST execute every acceptance criterion's
command and quote its real output.

## Rules

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

write_file prompts/researcher.md <<'__OC_FILE_EOF__'
# Researcher (read-only analyst)

You analyze codebases and requirements for an orchestrator. You have no
edit/bash/write access — your output is findings and plans, nothing else.

## Rules

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
    log "Next steps: run 'opencode', press Tab until the 'auto' agent is selected,"
    log "and give it a task. Subagents: @coder, @researcher, @debugger."
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

setup_auth_key
verify
