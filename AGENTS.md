# AGENTS.md

## Architecture

This directory configures the `opencode` AI assistant to use the GWDG SAIA OpenAI-compatible API (`https://chat-ai.academiccloud.de/v1`).

### Files

| File | Purpose |
|------|---------|
| `opencode.jsonc` | Main config: loads plugin + defines provider + agent config |
| `saia-gwdg-plugin.js` | Fetches live model list from GWDG at startup |
| `auth.json` (in `~/.local/share/opencode/`) | Stores API key (chmod 600) |
| `setup-gwdg.sh` | One-click setup script |

## Agents

| Agent | Role | Model | Temperature | Permissions | Color |
|-------|------|-------|-------------|-------------|-------|
| `build` | Primary | global/model | default | Full | default |
| `plan` | Primary | global/model | default | Ask (edit/bash) | warning (yellow) |
| `auto` | Primary | qwen3.5-397b-a17b | 0.3 | Full | - |
| `coder` | Subagent | qwen3-coder-next | 0.2 | Full | - |
| `researcher` | Subagent | qwen3.5-122b-a10b | 0.8 | Read-only | - |
| `debugger` | Subagent | devstral-2-123b | 0.3 | Full | - |

### Usage

- **Primary agents** (`build`, `plan`, `auto`): Press `Tab` to switch
- **Subagents** (`coder`, `researcher`, `debugger`): Invoke with `@coder`, `@researcher`, or `@debugger` in your message

### Auto Mode Workflow

When you press `Tab` to select `auto` and give it a task:
1. `auto` orchestrates → `@researcher` for analysis (read-only)
2. `auto` orchestrates → `@coder` for implementation (full tools)
3. `auto` orchestrates → `@debugger` for validation (full tools)

**Auto mode is restricted** - it cannot edit files, run bash, or write directly. It MUST delegate all work to subagents.

## Key Facts

- **API key location**: `~/.local/share/opencode/auth.json` (plaintext, chmod 600)
- **Model list**: Fetched dynamically from GWDG at each `opencode` invocation
- **Only ready models** are exposed (status check in plugin)
- Plugin auto-detects model capabilities (attachment support, reasoning)
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
