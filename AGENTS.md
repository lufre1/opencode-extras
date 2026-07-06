# AGENTS.md

## Architecture

This directory configures the `opencode` AI assistant to use the GWDG SAIA OpenAI-compatible API (`https://chat-ai.academiccloud.de/v1`).

### Files

| File | Purpose |
|------|---------|
| `opencode.jsonc` | Main config: loads plugin + defines provider base |
| `saia-gwdg-plugin.js` | Fetches live model list from GWDG at startup |
| `auth.json` (in `~/.local/share/opencode/`) | Stores API key (chmod 600) |
| `setup-gwdg.sh` | One-click setup script |

## Key Facts

- **API key location**: `~/.local/share/opencode/auth.json` (plaintext, chmod 600)
- **Model list**: Fetched dynamically from GWDG at each `opencode` invocation
- **Only ready models** are exposed (status check in plugin)
- Plugin auto-detects model capabilities (attachment support, reasoning)

## Commands

```bash
opencode              # start session using GWDG provider
opencode models       # list all available models
opencode providers    # show provider status
setup-gwdg.sh         # run setup (prompts for API key or uses GWDG_API_KEY env)
```

## Common Mistakes

- Editing `opencode.jsonc` instead of running `setup-gwdg.sh` → key won't load
- Moving `saia-gwdg-plugin.js` → absolute paths in config will break
- Deleting `auth.json` → plugin silently fails, no models loaded
- Running opencode before fetching models completes → empty model list
