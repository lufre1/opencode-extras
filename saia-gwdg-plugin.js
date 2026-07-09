import { readFileSync, writeFileSync, mkdirSync, appendFileSync } from "fs";
import { homedir } from "os";
import { join, dirname } from "path";

// SAIA rate limits are a single per-key bucket (30/min, 200/hour, 1000/day,
// 3000/month) and every /v1/models fetch counts against it. Cache the model
// list so repeated opencode startups don't burn requests; on fetch failure
// (offline, 429) fall back to a stale cache instead of loading no models.
const CACHE_PATH = join(homedir(), ".cache/opencode/saia-gwdg-models.json");
const CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours

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
      if (cached && Date.now() - cached.fetchedAt < CACHE_TTL_MS) {
        models = cached.models;
      } else {
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
