#!/usr/bin/env bash
#
# install-auto-mode.sh — GENERATED FILE, DO NOT EDIT.
# Regenerate with: ./build-installer.sh  (in the opencode config repo)
# Source: opencode-config commit b710e2a-dirty, packed 2026-07-13T18:22:06Z
#
# Installs the GWDG SAIA auto-mode setup for opencode: provider + plugin,
# agents (solo, auto, coder, coder2, researcher, debugger) with their
# prompts, the /reload_models helper script, and the API key in
# ~/.local/share/opencode/auth.json.
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
  "command": {
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
      "model": "saia-gwdg/qwen3.5-397b-a17b",
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

write_file saia-gwdg-plugin.js <<'__OC_FILE_EOF__'
import { readFileSync, writeFileSync, mkdirSync, appendFileSync } from "fs";
import { homedir } from "os";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

// The model list is cached for a week: the cache is authoritative while its
// fetchedAt is younger than MODELS_TTL_MS, so most launches cost zero SAIA
// requests. Older/missing cache triggers one /v1/models fetch (shared bucket:
// 30/min, 200/hour, 1000/day, 3000/month), with the stale cache as fallback
// on fetch failure. Force a refresh with /reload_models (runs
// reload-models.sh, which rewrites the cache with a fresh fetchedAt).
const CACHE_PATH = join(homedir(), ".cache/opencode/saia-gwdg-models.json");
const MODELS_TTL_MS = 7 * 24 * 60 * 60 * 1000;

// ---------------------------------------------------------------------------
// Request pacer: wraps globalThis.fetch for chat-ai.academiccloud.de only.
// - spaces request starts >= 2100ms apart so the 30/min limit can't trip
// - stops with a clear error when the hour/day bucket is nearly empty,
//   instead of letting opencode retry-spin 429s into a drained bucket
// - on 429, waits for the advertised reset once and retries; a second 429
//   throws
// - aborts after 3 consecutive 5xx responses: SAIA outages return 500s that
//   STILL consume the request budget, and opencode retries them with backoff
//   indefinitely — an unattended run would burn the bucket against a dead API
// Patching global fetch (not provider options.fetch) because opencode may
// not pass function-valued config through to the SDK.
// ---------------------------------------------------------------------------
const SAIA_HOST = "chat-ai.academiccloud.de";
const MIN_INTERVAL_MS = 2100;
const HOUR_FLOOR = 5;
const DAY_FLOOR = 10;
const MONTH_FLOOR = 30;
const MAX_CONSECUTIVE_5XX = 3;
const PACER_LOG = join(homedir(), ".cache/opencode/saia-gwdg-pacer.log");
const BUDGET_PATH = join(homedir(), ".cache/opencode/saia-gwdg-budget.json");

// Debug trail for everything the plugin decides (requests, cache hits,
// prompt injection). Only active with SAIA_PACER_DEBUG=1.
const pacerDebugLog = (line) => {
  if (process.env.SAIA_PACER_DEBUG !== "1") return;
  try {
    mkdirSync(dirname(PACER_LOG), { recursive: true });
    appendFileSync(PACER_LOG, `${new Date().toISOString()} ${line}\n`);
  } catch {}
};

function installPacer() {
  if (globalThis.__saiaPacerInstalled) return;
  globalThis.__saiaPacerInstalled = true;

  const realFetch = globalThis.fetch.bind(globalThis);
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  let queue = Promise.resolve(); // serializes SAIA requests
  let lastStart = 0;
  let remaining = { minute: null, hour: null, day: null, month: null };
  let consecutive5xx = 0;

  const readBuckets = (resp) => {
    let headerPresent = false;
    for (const b of ["minute", "hour", "day", "month"]) {
      const v = resp.headers.get(`x-ratelimit-remaining-${b}`);
      if (v !== null) {
        remaining[b] = Number(v);
        headerPresent = true;
      }
    }
    if (headerPresent) {
      try {
        mkdirSync(dirname(BUDGET_PATH), { recursive: true });
        writeFileSync(BUDGET_PATH, JSON.stringify({ updatedAt: new Date().toISOString(), remaining }));
      } catch {}
    }
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
      if (remaining.month !== null && remaining.month <= MONTH_FLOOR) {
        throw new Error(
          `SAIA monthly budget nearly exhausted (${remaining.month} requests left this month) — aborting.`
        );
      }
      if (consecutive5xx >= MAX_CONSECUTIVE_5XX) {
        throw new Error(
          `SAIA returned ${consecutive5xx} consecutive server errors (5xx) — the service ` +
            `looks down; aborting instead of retry-burning the request budget. Try again later.`
        );
      }

      const wait = lastStart + MIN_INTERVAL_MS - Date.now();
      if (wait > 0) await sleep(wait);
      lastStart = Date.now();

      let resp = await realFetch(input, init);
      readBuckets(resp);
      consecutive5xx = resp.status >= 500 ? consecutive5xx + 1 : 0;
      if (resp.status === 429) {
        const reset = Number(resp.headers.get("ratelimit-reset")) || 60;
        pacerDebugLog(`429 ${url.pathname} — waiting ${Math.min(reset, 65)}s before one retry`);
        await sleep(Math.min(reset, 65) * 1000);
        lastStart = Date.now();
        resp = await realFetch(input, init);
        readBuckets(resp);
        consecutive5xx = resp.status >= 500 ? consecutive5xx + 1 : 0;
        if (resp.status === 429) {
          throw new Error(
            `SAIA rate limit still exceeded after waiting (remaining: ` +
              `${remaining.minute}/min, ${remaining.hour}/hour, ${remaining.day}/day) — aborting.`
          );
        }
      }
      pacerDebugLog(
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
  // Solo workhorse: strongest tool-use coder, full-context single session.
  solo:       ["qwen3-coder-next", "glm-4.7"],
  // Orchestrator: best rule-following per request; deepseek-v4-flash demoted
  // (ignores prompt rules under task pressure — verified 2026-07-13).
  auto:       ["qwen3.5-122b-a10b", "qwen3.5-397b-a17b", "deepseek-v4-flash"],
  // Planning is the highest-leverage request in the chain: deepest reasoning.
  researcher: ["qwen3.5-397b-a17b", "qwen3.5-122b-a10b"],
  coder:      ["qwen3-coder-next", "glm-4.7"],
  // Fix rounds run on a DIFFERENT model family to break correlated errors.
  coder2:     ["glm-4.7", "mistral-medium-3.5-128b"],
  debugger:   ["qwen3-coder-next", "openai-gpt-oss-120b"],
  // devstral-2 is excluded everywhere: its SAIA chat template rejects
  // opencode's step-cap continuation ("Cannot set add_generation_prompt ...
  // last message is from the assistant"), burning a full step budget per try.
};

// Reads the pacer's latest budget snapshot; returns {hour, day, month}
// remaining counts if the snapshot is fresh (<15 min), else null.
function freshBudget() {
  try {
    const snap = JSON.parse(readFileSync(BUDGET_PATH, "utf-8"));
    const ageMin = (Date.now() - Date.parse(snap.updatedAt)) / 60000;
    const { hour, day, month } = snap.remaining ?? {};
    if (ageMin >= 0 && ageMin < 15 && typeof hour === "number") {
      return { hour, day: day ?? null, month: month ?? null };
    }
  } catch {}
  return null;
}

const LOW_HOUR_THRESHOLD = 40;
const LOW_DAY_THRESHOLD = 50;
const LOW_MONTH_THRESHOLD = 60;

// A chain/task shouldn't start when any bucket is too tight to fit one.
function budgetIsLow(b) {
  return (
    b.hour < LOW_HOUR_THRESHOLD ||
    (b.day !== null && b.day < LOW_DAY_THRESHOLD) ||
    (b.month !== null && b.month < LOW_MONTH_THRESHOLD)
  );
}

// Sessions that already have a subagent chain in flight: the budget gate only
// blocks STARTING a chain, never strangles one mid-run (the pacer's hard
// floor still protects the tail).
const chainStarted = new Set();

export const server = async (_input) => {
  return {
    // Code-enforced budget gate: the prompt-level gate is advisory only
    // (deepseek ignores it under task pressure), so the first `task` call of
    // a session is refused outright when the hourly budget can't fit a chain.
    "tool.execute.before": async (input, _output) => {
      if (input.tool !== "task") return;
      if (chainStarted.has(input.sessionID)) return;
      const b = freshBudget();
      if (b !== null && budgetIsLow(b)) {
        throw new Error(
          `SAIA budget LOW (${b.hour} left this hour, ${b.day ?? "?"} today, ${b.month ?? "?"} this month) — ` +
            `a subagent chain needs ~20-40 requests. Refusing to start the chain — ` +
            `report this to the user and stop; retry after the bucket resets.`
        );
      }
      chainStarted.add(input.sessionID);
    },

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
      if (
        typeof cached?.fetchedAt === "number" &&
        Date.now() - cached.fetchedAt < MODELS_TTL_MS &&
        cached.models
      ) {
        models = cached.models; // fresh enough — costs zero SAIA requests
        pacerDebugLog(
          `models: cache hit (age ${((Date.now() - cached.fetchedAt) / 86400000).toFixed(1)}d)`
        );
      } else {
        try {
          const resp = await fetch("https://chat-ai.academiccloud.de/v1/models", {
            headers: { Authorization: `Bearer ${key}` },
          });
          if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
          const json = await resp.json();
          models = json.data;
          pacerDebugLog("models: fetched fresh");
          try {
            mkdirSync(dirname(CACHE_PATH), { recursive: true });
            writeFileSync(CACHE_PATH, JSON.stringify({ fetchedAt: Date.now(), models }));
          } catch {}
        } catch {
          models = cached?.models; // stale cache beats no models
          pacerDebugLog("models: fetch failed, using stale cache");
        }
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

          pick = pick ?? anyReady;
          if (pick) agent.model = `saia-gwdg/${pick}`;
        }
      }

      // Budget check for the auto orchestrator. Its read tool can't reach
      // ~/.cache from a project session (external_directory permission is
      // auto-rejected in non-interactive runs), so the check happens here at
      // startup: read the pacer's last snapshot and bake a status line into
      // the auto prompt via the __SAIA_BUDGET_STATUS__ placeholder.
      let status = "UNKNOWN (no recent budget data)";
      const b = freshBudget();
      if (b !== null) {
        status =
          (budgetIsLow(b) ? "LOW" : "HEALTHY") +
          `: ${b.hour} requests left this hour, ${b.day ?? "?"} today, ` +
          `${b.month ?? "?"} this month (sustainable pace ≈100/day)`;
      }
      for (const [role, promptFile] of [
        ["auto", "prompts/auto.md"],
        ["solo", "prompts/solo.md"],
      ]) {
        try {
          const dir = dirname(fileURLToPath(import.meta.url));
          const txt = readFileSync(join(dir, promptFile), "utf-8");
          if (config.agent?.[role] && txt.includes("__SAIA_BUDGET_STATUS__")) {
            config.agent[role].prompt = txt.replaceAll("__SAIA_BUDGET_STATUS__", status);
            pacerDebugLog(`budget-status injected into ${role} prompt: ${status}`);
          } else {
            pacerDebugLog(
              `budget-status NOT injected into ${role} (agent=${!!config.agent?.[role]}, placeholder=${txt.includes("__SAIA_BUDGET_STATUS__")})`
            );
          }
        } catch (e) {
          pacerDebugLog(`budget-status injection failed for ${role}: ${e.message}`);
        }
      }
    },
  };
};
__OC_FILE_EOF__

write_file reload-models.sh <<'__OC_FILE_EOF__'
#!/usr/bin/env bash
#
# reload-models.sh — force-refresh the SAIA model list cache.
#
# Fetches /v1/models from GWDG (1 request of the shared rate budget) and
# rewrites ~/.cache/opencode/saia-gwdg-models.json with a fresh fetchedAt,
# so the plugin's weekly TTL restarts. Invoked by the /reload_models command
# or manually. The refreshed list takes effect at the NEXT opencode launch.
#
set -euo pipefail

AUTH_FILE="$HOME/.local/share/opencode/auth.json"
CACHE_FILE="$HOME/.cache/opencode/saia-gwdg-models.json"

KEY="$(python3 -c "
import json
print(json.load(open('$AUTH_FILE'))['saia-gwdg']['key'])
" 2>/dev/null)" || { echo "ERROR: could not read saia-gwdg key from $AUTH_FILE" >&2; exit 1; }

BODY="$(curl -sS --fail --max-time 60 https://chat-ai.academiccloud.de/v1/models \
  -H "Authorization: Bearer $KEY")" \
  || { echo "ERROR: /v1/models fetch failed — cache left untouched" >&2; exit 1; }

mkdir -p "$(dirname "$CACHE_FILE")"
BODY="$BODY" CACHE_FILE="$CACHE_FILE" python3 - <<'PYEOF'
import json, os, time
body = json.loads(os.environ["BODY"])
models = body["data"]
if not isinstance(models, list) or not models:
    raise SystemExit("ERROR: /v1/models returned no models — cache left untouched")
cache = os.environ["CACHE_FILE"]
tmp = cache + ".tmp"
with open(tmp, "w") as fh:
    json.dump({"fetchedAt": int(time.time() * 1000), "models": models}, fh)
os.replace(tmp, cache)
ready = sum(1 for m in models if m.get("status") == "ready")
print(f"Refreshed SAIA model cache: {len(models)} models, {ready} ready.")
print("Restart opencode to load the refreshed list (models are injected at startup).")
PYEOF
__OC_FILE_EOF__

write_file prompts/auto.md <<'__OC_FILE_EOF__'
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

write_file prompts/coder.md <<'__OC_FILE_EOF__'
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

write_file prompts/debugger.md <<'__OC_FILE_EOF__'
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

write_file prompts/researcher.md <<'__OC_FILE_EOF__'
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

write_file prompts/solo.md <<'__OC_FILE_EOF__'
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
    log "Next steps: run 'opencode', press Tab until the 'solo' agent (default"
    log "workhorse) or 'auto' (orchestrator for big tasks) is selected, and give"
    log "it a task. Subagents: @coder, @coder2, @researcher, @debugger."
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

chmod 755 "$CONFIG_DIR/reload-models.sh"
setup_auth_key
verify
