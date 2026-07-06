#!/usr/bin/env bash
#
# setup-gwdg.sh — Install and configure opencode for GWDG access
#
# Usage:
#   ./setup-gwdg.sh
#
# Prompts for GWDG API key interactively, or accepts GWDG_API_KEY env var.
#

CONFIG_DIR="$HOME/.config/opencode"
DATA_DIR="$HOME/.local/share/opencode"

# ── Get API key ──────────────────────────────────────────────────────

if [[ -n "${GWDG_API_KEY:-}" ]]; then
  API_KEY="$GWDG_API_KEY"
else
  echo -n "Enter your GWDG API key (from Academic Cloud portal): "
  read -r -s API_KEY
  echo
fi

if [[ -z "$API_KEY" ]]; then
  echo "Error: No API key provided."
  exit 1
fi

# ── Create directories ───────────────────────────────────────────────

mkdir -p "$CONFIG_DIR"
mkdir -p "$DATA_DIR"

# ── Write config files ───────────────────────────────────────────────

cat > "$CONFIG_DIR/opencode.jsonc" << 'EOF'
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
EOF

cat > "$CONFIG_DIR/saia-gwdg-plugin.js" << 'EOF'
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
EOF

cat > "$DATA_DIR/auth.json" << EOF
{
  "saia-gwdg": {
    "key": "${API_KEY}"
  }
}
EOF
chmod 600 "$DATA_DIR/auth.json"

# ── Done ─────────────────────────────────────────────────────────────

echo ""
echo "Done. GWDG setup is ready."
echo ""
echo "  opencode            # start interactive session"
echo "  opencode models     # list available GWDG models"
echo ""
echo "Note: Your API key is stored in $DATA_DIR/auth.json in plaintext."
