# SAIA-GWDG opencode setup

This directory configures the `opencode` AI assistant to use the GWDG SAIA OpenAI-compatible API.

## Quick start

Run the installer to set up on a new device:

```bash
GWDG_API_KEY="your-key" bash setup-saia-opencode.sh
```

Or see `SETUP.md` for detailed instructions and agent selection options.

## Files

| File | Purpose |
|------|---------|
| `opencode.jsonc` | Main config: loads plugin + defines provider + agent config |
| `saia-gwdg-plugin.js` | Fetches live model list from GWDG at startup |
| `prompts/` | Agent system prompts |
| `auth.json` | Stores API key (chmod 600) |
| `reload-models.sh` | Force-refresh the weekly SAIA model cache |
| `build-setup.sh` | Regenerates the installer |
| `setup-saia-opencode.sh` | Generated installer (never edit directly) |

## Setup

See `SETUP.md` for detailed installation instructions and agent selection.

## Architecture

```
auth.json → saia-gwdg-plugin.js → opencode.jsonc → https://chat-ai.academiccloud.de/v1
```

## Maintaining

After changing configuration files, regenerate the installer:

```bash
./build-setup.sh
```