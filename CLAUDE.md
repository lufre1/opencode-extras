# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

This is the user's `~/.config/opencode` directory, tracked in git. It configures the `opencode` AI assistant to use the GWDG SAIA OpenAI-compatible API (`https://chat-ai.academiccloud.de/v1`). There is no build, lint, or test tooling — changes are verified by running `opencode` itself.

## Commands

```bash
opencode              # start session (verifies config loads)
opencode models       # list models (weekly cache; fetches from GWDG only if cache >7d old)
opencode providers    # show provider status
./reload-models.sh    # force-refresh the model cache (1 API request; also via /reload_models in-session)
./build-installer.sh  # regenerate install-auto-mode.sh after config/plugin/prompt/script changes
```

## Architecture

Config resolution flows at every `opencode` startup:

1. `opencode.jsonc` — static config: registers the plugin, defines the `saia-gwdg` provider, and declares agents (`auto`, `coder`, `researcher`, `debugger`). Agent `model` values here are placeholders. Agent system prompts live in `prompts/*.md`, referenced via `"prompt": "{file:./prompts/auto.md}"`, keeping the jsonc slim (config + permissions only).
2. `saia-gwdg-plugin.js` — plugin's `config` hook runs at startup: installs a request pacer (wraps `globalThis.fetch` for the SAIA host: ≥2.1s between requests, one waited retry on 429, hard abort with a clear error when ≤5 hourly / ≤10 daily / ≤30 monthly requests remain or after 3 consecutive 5xx responses; always writes the latest remaining-budget counts to `~/.cache/opencode/saia-gwdg-budget.json` after every response that carries rate-limit headers; `SAIA_PACER_DEBUG=1` logs each request to `~/.cache/opencode/saia-gwdg-pacer.log`), reads the API key from `~/.local/share/opencode/auth.json`, loads the model list from the weekly cache (`~/.cache/opencode/saia-gwdg-models.json` is authoritative while its `fetchedAt` is <7 days old — most launches cost zero SAIA requests; older/missing cache triggers one `/v1/models` fetch, with the stale cache as failure fallback; force a refresh with `/reload_models` or `bash reload-models.sh`, then restart), injects only `status === "ready"` models into the provider (auto-detecting attachment/reasoning support), then **overwrites each agent's model** using the `ROLE_MODELS` preference table (first ready preference wins, else any ready model; the `auto` role additionally prefers reasoning-capable models). Finally it loads `prompts/auto.md` and `prompts/solo.md` itself and replaces the `__SAIA_BUDGET_STATUS__` placeholder with a LOW/HEALTHY/UNKNOWN budget status (hour/day/month counts) computed from the pacer's snapshot file. That prompt gate is advisory only (deepseek ignored it under task pressure) — the real enforcement is the plugin's `tool.execute.before` hook, which refuses the first `task` call of a session when the budget is LOW (<40 hour / <50 day / <60 month remaining; later task calls in the same session pass, so an in-flight chain is never cut off). Don't rename the placeholder or move the prompt files; agents must never try to read cache files themselves (reads outside the project are permission-blocked).
3. `~/.local/share/opencode/auth.json` (chmod 600, outside this repo) — holds the API key under the `saia-gwdg` key. If missing or unreadable, the plugin silently returns and no models load.

Key consequence: **to change which model an agent uses, edit `ROLE_MODELS` in `saia-gwdg-plugin.js`**, not the `model` fields in `opencode.jsonc` — the plugin overrides those at startup.

## Agent setup

- Primary agents (Tab to switch): built-in `build`/`plan`, plus `solo` (default workhorse) and `auto` (big/ambiguous multi-file tasks).
- **`solo`** (qwen3-coder-next, full tools, ~5–12 requests/task): plans inline, implements, self-checks in one session, then MUST task `@debugger` for independent validation (its only allowed subagent). Reach for it by default — SAIA bills per request, and solo avoids the chain's ~40% coordination overhead.
- **`auto`** is an orchestrator (qwen3.5-122b-a10b) with `edit`/`bash`/`write` denied but read-only access (read/glob/grep/list) for scoping and auditing. It delegates via `task` in a 5-phase loop defined in `prompts/auto.md`: intake → researcher PLAN (qwen3.5-397b, audited by auto; one-file fully-specified tasks skip the researcher — auto authors the PLAN itself) → coder CHANGES → debugger VERDICT (must run acceptance criteria and quote output) → fix loop capped at 1 round via `@coder2` (glm-4.7 — a different model family than the first coder, to avoid repeating the same mistake). It may declare success only on `VERDICT: PASS` with quoted evidence; otherwise it reports failures verbatim.
- Subagents (invoked as `@coder`, `@coder2`, `@researcher`, `@debugger`): coder (temp 0.2, full tools), coder2 (fix rounds, full tools), researcher (temp 0.2, read-only), debugger (temp 0.1, full tools). coder/researcher/debugger have system prompts in `prompts/<name>.md` defining structured output blocks (PLAN / CHANGES / VERDICT); coder2 reuses `prompts/coder.md`.

## Gotchas

- **`install-auto-mode.sh` is generated** by `build-installer.sh` from the live config files — never edit it directly, and regenerate + commit it after changing `opencode.jsonc`, `saia-gwdg-plugin.js`, or `prompts/*` (a stale installer silently ships old config to other devices). Don't run the installer on this machine to "refresh" the setup — the repo is the source of truth.
- **GWDG rate limits are tight and shared across everything**: one per-key bucket of 30 requests/min, 200/hour, 1000/day, 3000/month (see `x-ratelimit-*` response headers) covering chat completions AND `/v1/models`. Every agent step in an auto-mode run is one request. The plugin's pacer spaces requests so the per-minute limit can't trip and aborts with a clear error when the hourly/daily bucket is nearly empty — if a run dies with a "SAIA hourly budget nearly exhausted" error, that's the pacer working; wait for the reset. Check budget with a cheap 1-token chat request and `curl -D -` (`/v1/models` does NOT return rate-limit headers).
- In `agent.auto.permission.task` and `agent.solo.permission.task`, the `"*": "deny"` entry MUST be listed before the named allows — opencode resolves these last-match-wins, so a trailing `"*"` denies all subagents and silently removes the `task` tool from the orchestrator (verified empirically on 1.17.18).
- The `__SAIA_BUDGET_STATUS__` placeholder lives in BOTH `prompts/auto.md` and `prompts/solo.md` — the plugin substitutes it at startup; don't rename it in either file.
- Plugin failures are silent: missing/invalid `auth.json` or a failed models fetch with no usable cache means an empty model list with no error. A model list up to 7 days stale is *by design* (weekly TTL) — if GWDG adds/removes models mid-week, run `/reload_models` (from `solo`/`build`, needs bash) or `./reload-models.sh` and restart opencode.
- The plugin path in `opencode.jsonc` is relative (`./saia-gwdg-plugin.js`); don't move the plugin file.
- Agent prompts are loaded at startup via relative `{file:./prompts/*.md}` references — don't move or rename `prompts/` without updating `opencode.jsonc`.
- `.opencode.bak/` is an old backup of a previous config layout, not live config.
- `AGENTS.md` is read by opencode agents as their repo guidance — keep it in sync when changing agents or the plugin.
