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
| `tool/`, `skill/` | Scaffolds (with READMEs) for future opencode custom tools / skills — see [How the folders work](#how-the-folders-work) |
| `yagni.md` | Global instruction appended to every agent's prompt |
| `build-setup.sh` | Regenerates the installer |
| `setup-saia-opencode.sh` | Generated installer (never edit directly) |

The API key is **not** in the repo — the installer writes it to
`~/.local/share/opencode/auth.json` (chmod 600).

## How the folders work

The repo installs 1:1 into `~/.config/opencode`, and opencode **auto-discovers** several
of these folders — dropping a correctly-shaped file into one is all it takes to register a
prompt, command, tool, or skill. `build-setup.sh` globs the same folders when it
regenerates the installer, so anything you add ships automatically.

**`prompts/` — agent system prompts.** Each custom agent loads its prompt from here via
`"prompt": "{file:./prompts/*.md}"` in `opencode.jsonc`. The plugin
(`plugin/saia-gwdg-plugin.js`) also reads `prompts/auto.md` and `prompts/solo.md` at
startup and swaps the `__SAIA_BUDGET_STATUS__` placeholder for the live budget line. This
folder must stay a direct child of the config root — the plugin reads `../prompts/…`
relative to `plugin/`, and `{file:./prompts/*.md}` resolves relative to `opencode.jsonc`.

**`command/` + `scripts/` — slash commands and their backing scripts.** `command/*.md` are
auto-discovered slash commands (`/usage`, `/reload_models`). The markdown is thin: it
carries a `description` plus a one-line directive that runs the backing script — inline for
`usage.md`, via the bash tool for `reload_models.md`. The real work lives in `scripts/*.sh`
(`usage.sh`, `reload-models.sh`), installed to `~/.config/opencode/scripts/`.

**`tool/` — custom-tool scaffold (currently empty but for its README).** opencode
auto-discovers `*.js`/`*.ts` at the folder root and uses the filename as the tool name;
`build-setup.sh` packs `tool/*.js` / `tool/*.ts` into the installer. No tools exist yet —
see [`tool/README.md`](tool/README.md) for the authoring convention.

**`skill/` — skill scaffold (currently empty but for its README).** opencode auto-discovers
`skill/<name>/SKILL.md` (the directory name is the skill name); `build-setup.sh` packs
`skill/**/SKILL.md`. No skills exist yet — see [`skill/README.md`](skill/README.md) for the
authoring convention.

The `skill` tool is **disabled on every custom agent** (`"tools": { "skill": false }` on
`solo`, `auto`, `coder`, `coder2`, `researcher`, `debugger`), on purpose:

- Every tool call is a metered request against tight shared SAIA limits (see `AGENTS.md`),
  so an unused tool is pure cost.
- Fewer tools keep the small, single-job models focused and deterministic.
- There are no skills in the repo yet, so the tool would be all downside.

When you add a real skill, re-enable `skill: true` on just the agent(s) meant to invoke it.

**Why the empty `tool/` / `skill/` directories are kept.** They're auto-discovery mount
points: because `build-setup.sh` globs them (`tool/*.js` / `tool/*.ts`, `skill/**/SKILL.md`),
a real tool or skill added later ships with no config edit. `nullglob` means an empty folder
just ships nothing — no error. Their READMEs document the expected layout so contributors
get it right, and those scaffold READMEs are deliberately **not** packed into the installer.

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