# AGENTS.md

## Architecture

This directory configures the `opencode` AI assistant to use the GWDG SAIA OpenAI-compatible API (`https://chat-ai.academiccloud.de/v1`).

### Files

| File | Purpose |
|------|---------|
| `opencode.jsonc` | Main config: loads plugin + defines provider + agent config |
| `saia-gwdg-plugin.js` | Fetches live model list from GWDG at startup |
| `prompts/` | Agent system prompts, referenced via `{file:./prompts/*.md}` from opencode.jsonc |
| `auth.json` (in `~/.local/share/opencode/`) | Stores API key (chmod 600) |
| `setup-gwdg.sh` | One-click setup script (fresh installs only; does not reflect live config) |

## Agents

| Agent | Role | Model (plugin may override) | Temp | Steps | Permissions | Prompt |
|-------|------|-----------------------------|------|-------|-------------|--------|
| `build` | Primary | global/model | default | - | Full | built-in |
| `plan` | Primary | global/model | default | - | Ask (edit/bash) | built-in |
| `auto` | Primary | qwen3.5-122b-a10b (prefers reasoning-capable) | 0.2 | 40 | Read-only (read/glob/grep/list) + task | `prompts/auto.md` |
| `coder` | Subagent | qwen3-coder-next | 0.2 | 50 | Full | `prompts/coder.md` |
| `researcher` | Subagent | qwen3.5-122b-a10b | 0.2 | 25 | Read-only | `prompts/researcher.md` |
| `debugger` | Subagent | devstral-2-123b | 0.1 | 30 | Full | `prompts/debugger.md` |

### Usage

- **Primary agents** (`build`, `plan`, `auto`): Press `Tab` to switch
- **Subagents** (`coder`, `researcher`, `debugger`): Invoke with `@coder`, `@researcher`, or `@debugger` in your message

### Auto Mode Workflow

When you press `Tab` to select `auto` and give it a task, it runs a 5-phase loop:

1. **Intake** — auto scopes the task (it has read/glob/grep access for scoping and auditing only)
2. **Plan** — `@researcher` produces a PLAN block (goal, files, steps, runnable acceptance criteria); auto audits it (files exist, criteria are executable) before any coding
3. **Implement** — `@coder` executes the audited PLAN, returns a CHANGES block with self-check results
4. **Validate** — `@debugger` actually RUNS every acceptance criterion and returns VERDICT: PASS/FAIL with quoted command output
5. **Fix loop** — on FAIL, auto re-tasks coder with the failures verbatim and re-validates, max 3 rounds; then it must report failure honestly

**Auto mode cannot edit, write, or run bash** — it delegates all work. It may declare success only when the debugger returned `VERDICT: PASS` with real command output for every criterion; otherwise it reports the remaining failures verbatim.

## Key Facts

- **API key location**: `~/.local/share/opencode/auth.json` (plaintext, chmod 600)
- **Model list**: Fetched dynamically from GWDG at each `opencode` invocation
- **Only ready models** are exposed (status check in plugin)
- Plugin auto-detects model capabilities (attachment support, reasoning)
- Plugin overrides each agent's model via `ROLE_MODELS` in `saia-gwdg-plugin.js`; `auto` prefers a reasoning-capable model
- Built-in agents (`build`, `plan`) remain available alongside custom agents

## Commands

```bash
opencode              # start session with default (build) agent
opencode models       # list all available GWDG models
opencode providers    # show provider status
setup-gwdg.sh         # run setup (prompts for API key or uses GWDG_API_KEY env)
```

## Common Mistakes

- Editing `opencode.jsonc` instead of running `setup-gwdg.sh` → key won't load
- Moving `saia-gwdg-plugin.js` → absolute paths in config will break
- Deleting `auth.json` → plugin silently fails, no models loaded
- Running opencode before fetching models completes → empty model list
