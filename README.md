# SAIA-GWDG opencode setup

This directory configures the `opencode` AI assistant to use the GWDG SAIA OpenAI-compatible API.

## Quick start

Run the installer to set up on a new device:

```bash
GWDG_API_KEY="your-key" bash setup-saia-opencode.sh
```

Or see `SETUP.md` for detailed instructions and agent selection options.

## Files

The repo mirrors the installed `~/.config/opencode` layout and uses opencode's
auto-discovered folders.

| File / dir | Purpose |
|------------|---------|
| `opencode.jsonc` | Main config: provider + agent definitions (plugin & commands are auto-discovered from their folders — no `plugin`/`command` entries here) |
| `plugin/saia-gwdg-plugin.js` | Runtime plugin (auto-discovered): live model list, request pacer, budget tracking, prompt injection |
| `command/` | Custom slash commands as markdown — `/usage`, `/reload_models` |
| `scripts/` | Backing shell scripts for the commands (`usage.sh`, `reload-models.sh`) |
| `prompts/` | Agent system prompts, referenced via `{file:./prompts/*.md}` |
| `tool/`, `skill/` | Scaffolds (with READMEs) for future opencode custom tools / skills |
| `yagni.md` | Global instruction appended to every agent's prompt |
| `build-setup.sh` | Regenerates the installer |
| `setup-saia-opencode.sh` | Generated installer (never edit directly) |

The API key is **not** in the repo — the installer writes it to
`~/.local/share/opencode/auth.json` (chmod 600).

## Setup

See `SETUP.md` for detailed installation instructions and agent selection.

## Architecture

```
auth.json → plugin/saia-gwdg-plugin.js → opencode.jsonc → https://chat-ai.academiccloud.de/v1
```

## Maintaining

After changing configuration files, regenerate the installer:

```bash
./build-setup.sh
```