# OpenCode GWDG Setup

## Prerequisites

- [opencode](https://github.com/sst/opencode) installed and available in your PATH

That's it. No Node.js, npm, or dependencies to install.

## Quick Install

Run the setup script:

```bash
bash setup-gwdg.sh
```

If your environment provides an API key via env var, it will be used automatically:

```bash
GWDG_API_KEY="your-key" bash setup-gwdg.sh
```

## Manual Install

You only need 3 files.

### 1. `~/.config/opencode/opencode.jsonc`

```jsonc
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
  }
}
```

### 2. `~/.config/opencode/saia-gwdg-plugin.js`

This plugin reads your API key, dynamically fetches available models from GWDG,
and injects them into the provider config:

```js
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
```

### 3. `~/.local/share/opencode/auth.json`

```bash
mkdir -p ~/.local/share/opencode

cat > ~/.local/share/opencode/auth.json << EOF
{
  "saia-gwdg": {
    "key": "your-gwdg-api-key-here"
  }
}
EOF
chmod 600 ~/.local/share/opencode/auth.json
```

> ⚠️ Your API key is stored in plaintext. Ensure the machine is secure.

## Architecture

```
auth.json (API key, chmod 600)
    │
    ▼
saia-gwdg-plugin.js (reads key, fetches models at startup)
    │
    ▼
opencode.jsonc (provider config + dynamic model list)
    │
    ▼
https://chat-ai.academiccloud.de/v1  (GWDG OpenAI-compatible API)
```

## Usage

```bash
opencode                        # interactive session
opencode models                 # list all available GWDG models
opencode providers              # view provider status
```

The plugin fetches the available model list each time opencode starts.
