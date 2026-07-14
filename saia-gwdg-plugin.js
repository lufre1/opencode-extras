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
  // Planning is the highest-leverage request in the chain. qwen3.5-397b was
  // removed entirely: its endpoint hung on 3 of 4 dispatches (2026-07-13/14),
  // stalling the whole chain — a "ready"-but-hanging model is worse than none.
  researcher: ["qwen3.5-122b-a10b", "qwen3-coder-next"],
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
