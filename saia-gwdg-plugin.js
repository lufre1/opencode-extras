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
// - supports multiple API keys with hard-floor failover: rate limits are
//   per key, and opencode only knows the auth.json key, so the pacer
//   rewrites the Authorization header to the active key on every request.
//   When the active key's hour/day/month bucket is nearly empty (or it
//   429s despite pacing) the pacer switches to the next usable key; an
//   exhausted key re-enters rotation after its bucket's reset TTL. Extra
//   keys live in KEYS_PATH; without that file this is single-key as before.
// - stops with a clear error only when EVERY key is nearly exhausted,
//   instead of letting opencode retry-spin 429s into drained buckets
// - on 429, waits for the advertised reset once and retries; a second 429
//   fails the key over; a 429 on the next key too throws
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
const KEYS_PATH = join(homedir(), ".local/share/opencode/saia-gwdg-keys.json");
// How long an exhausted bucket keeps a key out of rotation before it is
// optimistically retried (the true state is learned from the next headers).
const RESET_TTL_MS = { hour: 60 * 60000, day: 24 * 3600000, month: 30 * 86400000 };

// Debug trail for everything the plugin decides (requests, cache hits,
// prompt injection). Only active with SAIA_PACER_DEBUG=1.
const pacerDebugLog = (line) => {
  if (process.env.SAIA_PACER_DEBUG !== "1") return;
  try {
    mkdirSync(dirname(PACER_LOG), { recursive: true });
    appendFileSync(PACER_LOG, `${new Date().toISOString()} ${line}\n`);
  } catch {}
};

function installPacer(keys) {
  // The wrapper closure reads this global, so a config-hook re-run can
  // refresh the key list without re-wrapping fetch.
  globalThis.__saiaKeys = keys;
  if (globalThis.__saiaPacerInstalled) return;
  globalThis.__saiaPacerInstalled = true;

  const realFetch = globalThis.fetch.bind(globalThis);
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  let queue = Promise.resolve(); // serializes SAIA requests
  let lastStart = 0;
  let consecutive5xx = 0; // global: an outage is key-independent
  let activeIndex = 0;

  const FLOORS = { hour: HOUR_FLOOR, day: DAY_FLOOR, month: MONTH_FLOOR };

  // Per-key pacer state, keyed by the key string so a refreshed key list
  // keeps what was already learned.
  const stateByKey = new Map();
  const stateFor = (key) => {
    let s = stateByKey.get(key);
    if (!s) {
      s = {
        remaining: { minute: null, hour: null, day: null, month: null },
        exhausted: { hour: 0, day: 0, month: 0 },
        updatedAt: null,
      };
      stateByKey.set(key, s);
    }
    return s;
  };

  const label = (key) => `key${globalThis.__saiaKeys.indexOf(key) + 1}(…${key.slice(-4)})`;

  const markExhausted = (key, bucket) => {
    const s = stateFor(key);
    s.exhausted[bucket] = Date.now();
    s.remaining[bucket] = null; // forget the count; retry optimistically after the TTL
    pacerDebugLog(`${label(key)} exhausted (${bucket} bucket)`);
  };

  // Converts floored remaining counts into exhaustion stamps, then reports
  // whether the key is currently usable.
  const keyUsable = (key) => {
    const s = stateFor(key);
    let usable = true;
    for (const b of ["hour", "day", "month"]) {
      if (s.remaining[b] !== null && s.remaining[b] <= FLOORS[b]) markExhausted(key, b);
      if (s.exhausted[b]) {
        if (Date.now() - s.exhausted[b] < RESET_TTL_MS[b]) usable = false;
        else s.exhausted[b] = 0; // TTL passed — the bucket has reset
      }
    }
    return usable;
  };

  // The active key while it has budget, else the next usable key (wrapping
  // around). Returns null when every key is exhausted.
  const pickKey = () => {
    const all = globalThis.__saiaKeys ?? [];
    if (all.length === 0) return null;
    if (activeIndex >= all.length) activeIndex = 0;
    const before = activeIndex;
    for (let i = 0; i < all.length; i++) {
      const idx = (before + i) % all.length;
      if (keyUsable(all[idx])) {
        if (idx !== before) pacerDebugLog(`switching ${label(all[before])} -> ${label(all[idx])}`);
        activeIndex = idx;
        return all[idx];
      }
    }
    return null;
  };

  const allExhaustedError = () => {
    const all = globalThis.__saiaKeys;
    const per = all.map((k) => {
      const s = stateFor(k);
      const buckets = ["hour", "day", "month"].filter(
        (b) => s.exhausted[b] && Date.now() - s.exhausted[b] < RESET_TTL_MS[b]
      );
      return `${label(k)}: ${buckets.join("+") || "exhausted"}`;
    });
    return new Error(
      `All ${all.length} SAIA key(s) nearly exhausted (${per.join("; ")}) — ` +
        `aborting instead of retry-spinning. Wait for the buckets to reset.`
    );
  };

  // Rate limits are per key, but opencode only knows the auth.json key —
  // rewrite the Authorization header to the currently active one.
  // NOTE: when both a Request object and an init are passed, init.headers
  // wins in fetch() — so the rewrite must always land on the init side
  // (rewriting only the Request would silently keep the old key).
  const withAuth = (input, init, key) => {
    const base =
      init?.headers ?? (typeof Request !== "undefined" && input instanceof Request ? input.headers : undefined);
    const headers = new Headers(base);
    headers.set("authorization", `Bearer ${key}`);
    return [input, { ...init, headers }];
  };

  const writeSnapshot = () => {
    const all = globalThis.__saiaKeys;
    try {
      mkdirSync(dirname(BUDGET_PATH), { recursive: true });
      writeFileSync(
        BUDGET_PATH,
        JSON.stringify({
          updatedAt: new Date().toISOString(),
          activeIndex,
          // top-level `remaining` mirrors the active key for old readers
          remaining: stateFor(all[activeIndex]).remaining,
          keys: all.map((k) => {
            const s = stateFor(k);
            return { label: label(k), updatedAt: s.updatedAt, remaining: s.remaining, exhausted: s.exhausted };
          }),
        })
      );
    } catch {}
  };

  const readBuckets = (resp, key) => {
    const s = stateFor(key);
    let headerPresent = false;
    for (const b of ["minute", "hour", "day", "month"]) {
      const v = resp.headers.get(`x-ratelimit-remaining-${b}`);
      if (v !== null) {
        s.remaining[b] = Number(v);
        headerPresent = true;
      }
    }
    if (headerPresent) {
      s.updatedAt = new Date().toISOString();
      writeSnapshot();
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
      if (consecutive5xx >= MAX_CONSECUTIVE_5XX) {
        throw new Error(
          `SAIA returned ${consecutive5xx} consecutive server errors (5xx) — the service ` +
            `looks down; aborting instead of retry-burning the request budget. Try again later.`
        );
      }
      let key = pickKey();
      if (key === null) throw allExhaustedError();

      const attempt = async (k) => {
        const wait = lastStart + MIN_INTERVAL_MS - Date.now();
        if (wait > 0) await sleep(wait);
        lastStart = Date.now();
        const resp = await realFetch(...withAuth(input, init, k));
        readBuckets(resp, k);
        consecutive5xx = resp.status >= 500 ? consecutive5xx + 1 : 0;
        return resp;
      };

      let resp = await attempt(key);
      if (resp.status === 429) {
        const reset = Number(resp.headers.get("ratelimit-reset")) || 60;
        pacerDebugLog(`429 ${url.pathname} on ${label(key)} — waiting ${Math.min(reset, 65)}s before one retry`);
        await sleep(Math.min(reset, 65) * 1000);
        resp = await attempt(key);
        if (resp.status === 429) {
          // out of budget despite pacing — fail this key over, try the next once
          markExhausted(key, "hour");
          writeSnapshot();
          key = pickKey();
          if (key === null) throw allExhaustedError();
          pacerDebugLog(`429 twice — retrying once on ${label(key)}`);
          resp = await attempt(key);
          if (resp.status === 429) {
            const s = stateFor(key);
            throw new Error(
              `SAIA rate limit still exceeded after waiting and switching keys (remaining on ${label(key)}: ` +
                `${s.remaining.minute}/min, ${s.remaining.hour}/hour, ${s.remaining.day}/day) — aborting.`
            );
          }
        }
      }
      const s = stateFor(key);
      pacerDebugLog(
        `${resp.status} ${url.pathname} ${label(key)} remaining=${s.remaining.minute}/min ${s.remaining.hour}/hour ${s.remaining.day}/day`
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

const BUCKET_LIMITS = { hour: 200, day: 1000, month: 3000 };

// Reads the pacer's latest budget snapshot and aggregates remaining counts
// across all keys. A key without a fresh (<15 min) per-key snapshot counts
// as full — the same optimism the pacer itself has for untouched keys.
// Returns {hour, day, month, keyCount}, or null when no key has fresh data.
function freshBudget() {
  try {
    const snap = JSON.parse(readFileSync(BUDGET_PATH, "utf-8"));
    const entries =
      Array.isArray(snap.keys) && snap.keys.length
        ? snap.keys
        : [{ updatedAt: snap.updatedAt, remaining: snap.remaining }]; // pre-multi-key format
    const total = { hour: 0, day: 0, month: 0 };
    let anyFresh = false;
    for (const e of entries) {
      const ageMin = (Date.now() - Date.parse(e.updatedAt)) / 60000;
      const fresh = ageMin >= 0 && ageMin < 15 && typeof e.remaining?.hour === "number";
      if (fresh) anyFresh = true;
      for (const b of ["hour", "day", "month"]) {
        // a bucket the pacer stamped exhausted counts as empty until its TTL
        // passes (markExhausted nulls the count, so `remaining` can't tell)
        const stamp = e.exhausted?.[b];
        if (typeof stamp === "number" && stamp > 0 && Date.now() - stamp < RESET_TTL_MS[b]) {
          anyFresh = true;
          continue;
        }
        total[b] += fresh && typeof e.remaining[b] === "number" ? e.remaining[b] : BUCKET_LIMITS[b];
      }
    }
    if (anyFresh) return { ...total, keyCount: entries.length };
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
          `SAIA budget LOW (~${b.hour} left this hour across ${b.keyCount} key(s), ` +
            `~${b.day} today, ~${b.month} this month) — ` +
            `a subagent chain needs ~20-40 requests. Refusing to start the chain — ` +
            `report this to the user and stop; retry after the bucket resets.`
        );
      }
      chainStarted.add(input.sessionID);
    },

    config: async (config) => {
      let key;
      try {
        const authPath = join(homedir(), ".local/share/opencode/auth.json");
        const auth = JSON.parse(readFileSync(authPath, "utf-8"));
        key = auth["saia-gwdg"]?.key;
      } catch {
        return;
      }

      if (!key) return;

      // Optional failover keys: KEYS_PATH holds {"keys": ["...", ...]} in
      // rotation order after the auth.json key (always #1). A missing or
      // unreadable file means single-key behavior, exactly as before.
      let keys = [key];
      try {
        const extra = JSON.parse(readFileSync(KEYS_PATH, "utf-8"));
        if (Array.isArray(extra?.keys)) {
          keys = [...new Set([key, ...extra.keys.filter((k) => typeof k === "string" && k)])];
        }
      } catch {}
      installPacer(keys);
      pacerDebugLog(`pacer: ${keys.length} SAIA key(s) in rotation`);

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
          `: ~${b.hour} requests left this hour across ${b.keyCount} key(s), ~${b.day} today, ` +
          `~${b.month} this month (sustainable pace ≈${100 * b.keyCount}/day)`;
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
