import { readFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";

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

      let models;
      try {
        const resp = await fetch("https://chat-ai.academiccloud.de/v1/models", {
          headers: { Authorization: `Bearer ${key}` },
        });
        if (!resp.ok) return;
        const json = await resp.json();
        models = json.data;
      } catch {
        return;
      }

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
    },
  };
};
