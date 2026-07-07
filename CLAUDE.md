# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

This is the user's `~/.config/opencode` directory, tracked in git. It configures the `opencode` AI assistant to use the GWDG SAIA OpenAI-compatible API (`https://chat-ai.academiccloud.de/v1`). There is no build, lint, or test tooling — changes are verified by running `opencode` itself.

## Commands

```bash
opencode              # start session (verifies config loads)
opencode models       # list models fetched from GWDG — confirms plugin + API key work
opencode providers    # show provider status
bash setup-gwdg.sh    # fresh install: writes config files + auth.json (see warning below)
```

## Architecture

Config resolution flows at every `opencode` startup:

1. `opencode.jsonc` — static config: registers the plugin, defines the `saia-gwdg` provider, and declares agents (`auto`, `coder`, `researcher`, `debugger`). Agent `model` values here are placeholders. Agent system prompts live in `prompts/*.md`, referenced via `"prompt": "{file:./prompts/auto.md}"`, keeping the jsonc slim (config + permissions only).
2. `saia-gwdg-plugin.js` — plugin's `config` hook runs at startup: reads the API key from `~/.local/share/opencode/auth.json`, fetches the live model list from GWDG, injects only `status === "ready"` models into the provider (auto-detecting attachment/reasoning support), then **overwrites each agent's model** using the `ROLE_MODELS` preference table (first ready preference wins, else any ready model; the `auto` role additionally prefers reasoning-capable models).
3. `~/.local/share/opencode/auth.json` (chmod 600, outside this repo) — holds the API key under the `saia-gwdg` key. If missing or unreadable, the plugin silently returns and no models load.

Key consequence: **to change which model an agent uses, edit `ROLE_MODELS` in `saia-gwdg-plugin.js`**, not the `model` fields in `opencode.jsonc` — the plugin overrides those at startup.

## Agent setup

- Primary agents (Tab to switch): built-in `build`/`plan`, plus `auto`.
- Subagents (invoked as `@coder`, `@researcher`, `@debugger`): coder (temp 0.2, full tools), researcher (temp 0.2, read-only), debugger (temp 0.1, full tools). Each has a system prompt in `prompts/<name>.md` defining a structured output block (PLAN / CHANGES / VERDICT).
- `auto` is an orchestrator with `edit`/`bash`/`write` denied but read-only access (read/glob/grep/list) for scoping and auditing. It delegates via `task` in a 5-phase loop defined in `prompts/auto.md`: intake → researcher PLAN (audited by auto) → coder CHANGES → debugger VERDICT (must run acceptance criteria and quote output) → fix loop capped at 3 rounds. It may declare success only on `VERDICT: PASS` with quoted evidence; otherwise it reports failures verbatim.

## Gotchas

- **`setup-gwdg.sh` clobbers config**: it rewrites `opencode.jsonc` and `saia-gwdg-plugin.js` from embedded heredocs that are older than the live files (no `ROLE_MODELS`, no agent definitions, no `prompts/`). It is for fresh installs only — do not run it on this machine to "refresh" the setup.
- Plugin failures are silent: missing/invalid `auth.json` or a failed models fetch means an empty model list with no error.
- The plugin path in `opencode.jsonc` is relative (`./saia-gwdg-plugin.js`); don't move the plugin file.
- Agent prompts are loaded at startup via relative `{file:./prompts/*.md}` references — don't move or rename `prompts/` without updating `opencode.jsonc`.
- `.opencode.bak/` is an old backup of a previous config layout, not live config.
- `AGENTS.md` is read by opencode agents as their repo guidance — keep it in sync when changing agents or the plugin.
