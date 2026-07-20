# CLAUDE.md

This file provides guidance to Claude Code when working with this opencode SAIA setup.

## Quick reference

- **Build command:** `./build-setup.sh` — regenerates `setup-saia-opencode.sh` after config changes
- **Install:** `bash setup-saia-opencode.sh` (interactive prompts for agent selection) or `--yes`/`--solo`/`--auto` flags
- **Model refresh:** `/reload_models` in opencode or `bash scripts/reload-models.sh`, then restart opencode

## Architecture

The repo uses opencode's auto-discovered folders (installed 1:1 into `~/.config/opencode`).

1. `opencode.jsonc` — static config (provider + inline agent definitions; no `plugin`/`command` blocks)
2. `plugin/saia-gwdg-plugin.js` — runtime plugin, **auto-discovered** from `plugin/` (model list, budget tracking, prompt injection)
3. `command/*.md` — slash commands (`/usage`, `/reload_models`), auto-discovered; backed by `scripts/*.sh`
4. `prompts/*.md` — agent system prompts (loaded at runtime)
5. `tool/`, `skill/` — scaffolds for future custom tools / skills

## Gotchas

- `setup-saia-opencode.sh` is generated — never edit directly; regenerate after any config change
- Rate limits: 30 req/min, 200/hour, 1000/day, 3000/month shared across all agents
- In `opencode.jsonc`, `"*": "deny"` in `agent.auto.permission.task` and `agent.solo.permission.task` MUST come before named allows (last-match-wins)
- `__SAIA_BUDGET_STATUS__` placeholder in `prompts/auto.md` and `prompts/solo.md` — never rename
- Plugin silently fails if `auth.json` is missing or models fetch fails with no valid cache
- Plugin & commands are auto-discovered — do NOT re-add a `plugin` array or `command` block to `opencode.jsonc`
- `prompts/` must stay a direct child of the config root: the plugin reads `../prompts/{auto,solo}.md` from `plugin/`, and `{file:./prompts/*.md}` resolves relative to `opencode.jsonc`
- `build-setup.sh` glob-packs `tool/*.{js,ts}` and `skill/**/SKILL.md`, so real tools/skills added to those folders ship automatically (the scaffold READMEs are not packed)
- `.opencode.bak/` is an old backup — gitignored

See `AGENTS.md` for detailed agent architecture and `SETUP.md` for installation instructions.
