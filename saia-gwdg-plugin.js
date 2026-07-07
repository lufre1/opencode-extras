import { readFileSync, writeFileSync, mkdirSync } from "fs";
import { homedir } from "os";
import { join, dirname } from "path";

// SAIA rate limits are a single per-key bucket (30/min, 200/hour, 1000/day,
// 3000/month) and every /v1/models fetch counts against it. Cache the model
// list so repeated opencode startups don't burn requests; on fetch failure
// (offline, 429) fall back to a stale cache instead of loading no models.
const CACHE_PATH = join(homedir(), ".cache/opencode/saia-gwdg-models.json");
const CACHE_TTL_MS = 60 * 60 * 1000; // 1 hour

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
