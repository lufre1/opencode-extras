# CLAUDE.md

This file provides guidance to Claude Code when working with this opencode SAIA setup.

## Quick reference

- **Build command:** `./build-setup.sh` — regenerates `setup-saia-opencode.sh` after config changes
- **Install:** `bash setup-saia-opencode.sh` (interactive prompts for agent selection) or `--yes`/`--solo`/`--auto` flags
- **Model refresh:** `/reload_models` in opencode or `bash reload-models.sh`, then restart opencode

## Architecture

1. `opencode.jsonc` — static config (provider + agents metadata)
2. `saia-gwdg-plugin.js` — runtime plugin (model list, budget tracking, prompt injection)
3. `prompts/*.md` — agent system prompts (loaded at runtime)

## Gotchas

- `setup-saia-opencode.sh` is generated — never edit directly; regenerate after any config change
- Rate limits: 30 req/min, 200/hour, 1000/day, 3000/month shared across all agents
- In `opencode.jsonc`, `"*": "deny"` in `agent.auto.permission.task` and `agent.solo.permission.task` MUST come before named allows (last-match-wins)
- `__SAIA_BUDGET_STATUS__` placeholder in `prompts/auto.md` and `prompts/solo.md` — never rename
- Plugin silently fails if `auth.json` is missing or models fetch fails with no valid cache
- Plugin path must be relative (`./saia-gwdg-plugin.js`)
- `.opencode.bak/` is an old backup — gitignored

See `AGENTS.md` for detailed agent architecture and `SETUP.md` for installation instructions.
