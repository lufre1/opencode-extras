# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

This is the user's `~/.config/opencode` directory, tracked in git. It configures the `opencode` AI assistant to use the GWDG SAIA OpenAI-compatible API (`https://chat-ai.academiccloud.de/v1`). There is no build, lint, or test tooling — changes are verified by running `opencode` itself.

## Commands

```bash
opencode              # start session (verifies config loads)
opencode models       # list models fetched from GWDG — confirms plugin + API key work
opencode providers    # show provider status
./build-installer.sh  # regenerate install-auto-mode.sh after config/plugin/prompt changes
```

## Architecture

Config resolution flows at every `opencode` startup:

1. `opencode.jsonc` — static config: registers the plugin, defines the `saia-gwdg` provider, and declares agents (`auto`, `coder`, `researcher`, `debugger`). Agent `model` values here are placeholders. Agent system prompts live in `prompts/*.md`, referenced via `"prompt": "{file:./prompts/auto.md}"`, keeping the jsonc slim (config + permissions only).
2. `saia-gwdg-plugin.js` — plugin's `config` hook runs at startup: installs a request pacer (wraps `globalThis.fetch` for the SAIA host: ≥2.1s between requests, one waited retry on 429, hard abort with a clear error when ≤5 hourly / ≤10 daily requests remain; `SAIA_PACER_DEBUG=1` logs each request to `~/.cache/opencode/saia-gwdg-pacer.log`), reads the API key from `~/.local/share/opencode/auth.json`, fetches the live model list from GWDG (cached 24h in `~/.cache/opencode/saia-gwdg-models.json`; stale cache is used if the fetch fails), injects only `status === "ready"` models into the provider (auto-detecting attachment/reasoning support), then **overwrites each agent's model** using the `ROLE_MODELS` preference table (first ready preference wins, else any ready model; the `auto` role additionally prefers reasoning-capable models).
3. `~/.local/share/opencode/auth.json` (chmod 600, outside this repo) — holds the API key under the `saia-gwdg` key. If missing or unreadable, the plugin silently returns and no models load.

Key consequence: **to change which model an agent uses, edit `ROLE_MODELS` in `saia-gwdg-plugin.js`**, not the `model` fields in `opencode.jsonc` — the plugin overrides those at startup.

## Agent setup

- Primary agents (Tab to switch): built-in `build`/`plan`, plus `auto`.
- Subagents (invoked as `@coder`, `@researcher`, `@debugger`): coder (temp 0.2, full tools), researcher (temp 0.2, read-only), debugger (temp 0.1, full tools). Each has a system prompt in `prompts/<name>.md` defining a structured output block (PLAN / CHANGES / VERDICT).
- `auto` is an orchestrator with `edit`/`bash`/`write` denied but read-only access (read/glob/grep/list) for scoping and auditing. It delegates via `task` in a 5-phase loop defined in `prompts/auto.md`: intake → researcher PLAN (audited by auto; one-file fully-specified tasks skip the researcher — auto authors the PLAN itself) → coder CHANGES → debugger VERDICT (must run acceptance criteria and quote output) → fix loop capped at 1 round. It may declare success only on `VERDICT: PASS` with quoted evidence; otherwise it reports failures verbatim.

## Gotchas

- **`install-auto-mode.sh` is generated** by `build-installer.sh` from the live config files — never edit it directly, and regenerate + commit it after changing `opencode.jsonc`, `saia-gwdg-plugin.js`, or `prompts/*` (a stale installer silently ships old config to other devices). Don't run the installer on this machine to "refresh" the setup — the repo is the source of truth.
- **GWDG rate limits are tight and shared across everything**: one per-key bucket of 30 requests/min, 200/hour, 1000/day, 3000/month (see `x-ratelimit-*` response headers) covering chat completions AND `/v1/models`. Every agent step in an auto-mode run is one request. The plugin's pacer spaces requests so the per-minute limit can't trip and aborts with a clear error when the hourly/daily bucket is nearly empty — if a run dies with a "SAIA hourly budget nearly exhausted" error, that's the pacer working; wait for the reset. Check budget with a cheap 1-token chat request and `curl -D -` (`/v1/models` does NOT return rate-limit headers).
- Plugin failures are silent: missing/invalid `auth.json` or a failed models fetch with no usable cache means an empty model list with no error.
- The plugin path in `opencode.jsonc` is relative (`./saia-gwdg-plugin.js`); don't move the plugin file.
- Agent prompts are loaded at startup via relative `{file:./prompts/*.md}` references — don't move or rename `prompts/` without updating `opencode.jsonc`.
- `.opencode.bak/` is an old backup of a previous config layout, not live config.
- `AGENTS.md` is read by opencode agents as their repo guidance — keep it in sync when changing agents or the plugin.
