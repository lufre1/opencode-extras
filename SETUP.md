# Installing SAIA setup on another device

Everything ships in one generated script: `setup-saia-opencode.sh`.

## Fresh device

```bash
scp setup-saia-opencode.sh otherhost:
ssh otherhost
GWDG_API_KEY="your-key" bash setup-saia-opencode.sh    # or run without the env var to be prompted
```

What it does:

1. Checks for `opencode` (also looks in `~/.opencode/bin`); if missing, offers to run the official installer (`curl -fsSL https://opencode.ai/install | bash`).
2. Writes `opencode.jsonc`, `saia-gwdg-plugin.js`, and selected `prompts/*.md` into `~/.config/opencode/`. Files that would be overwritten are backed up to `~/.config/opencode.bak-<timestamp>/` first; unchanged files are left alone (rerunning is safe).
3. Writes the API key to `~/.local/share/opencode/auth.json` (chmod 600) as `{"saia-gwdg": {"type": "api", "key": "..."}}`, merging into an existing auth.json rather than clobbering other providers. An existing saia-gwdg key is kept unless `--force-key` is passed.
4. Verifies by running `opencode models` and checking that `saia-gwdg/` models are listed (costs 1 request of the shared GWDG rate budget: 30/min, 200/hour per key).

### Agent selection

The installer defaults to opt-in—no agents are installed unless specified:

- **Interactive mode (default)**: Prompts for each agent (solo, auto)
- **Non-interactive (`--yes`)**: Skips all agents (minimal install)
- **Explicit flags**: Use `--solo`, `--auto`, `--no-solo`, `--no-auto` to control

```bash
# Install with only solo agent
GWDG_API_KEY="key" bash setup-saia-opencode.sh --solo

# Install with both agents
GWDG_API_KEY="key" bash setup-saia-opencode.sh --solo --auto

# Non-interactive: skip all agents (minimal install)
GWDG_API_KEY="key" bash setup-saia-opencode.sh --yes

# Non-interactive: install auto only, skip solo
GWDG_API_KEY="key" bash setup-saia-opencode.sh --yes --auto
```

Flags:
- `-y, --yes` — non-interactive mode (skips all agents)
- `--solo` — install the solo agent (default: ask)
- `--auto` — install the auto agent (default: ask)
- `--no-solo` — skip the solo agent (default: ask)
- `--no-auto` — skip the auto agent (default: ask)
- `--force-key` — replace an existing saia-gwdg API key
- `-h, --help` — show usage

## Maintaining the installer (on this machine)

`setup-saia-opencode.sh` is **generated** — never edit it directly. After changing `opencode.jsonc`, `saia-gwdg-plugin.js`, or `prompts/*.md`:

```bash
./build-setup.sh    # regenerates setup-saia-opencode.sh from the live files
git add -A && git commit
```

The generator refuses to run if a packed file contains the heredoc delimiter or lacks a trailing newline, and stamps the output with the source git commit and pack date (the stamp identifies the config content; the commit *containing* the installer is one later). It warns if the packed files have uncommitted changes (`-dirty` stamp).

## Architecture on the target device

```
auth.json (API key, chmod 600, ~/.local/share/opencode/)
    │
    ▼
saia-gwdg-plugin.js (reads key, fetches models — cached 1h — assigns agent models)
    │
    ▼
opencode.jsonc (provider + agents; prompts via {file:./prompts/*.md})
    │
    ▼
https://chat-ai.academiccloud.de/v1  (GWDG OpenAI-compatible API)
```

## Usage after install

```bash
opencode              # interactive session; press Tab to select agent
opencode models       # list available GWDG models
```

### Available agents

**Primary agents:**
- `build` — built-in, always available
- `plan` — built-in, always available
- `solo` — default workhorse (~5-12 requests/task)
- `auto` — orchestrator for big tasks (~20-40 requests/task)

**Subagents:**
- `@coder`, `@coder2` — implementers
- `@researcher` — analyst (PLAN blocks)
- `@debugger` — validator (runs acceptance criteria)

## Minimal install (no agents)

To install only the provider/plugin without any custom agents, use:

```bash
GWDG_API_KEY="your-key" bash setup-saia-opencode.sh --yes
```

This installs:
- Provider configuration (`opencode.jsonc`, `saia-gwdg-plugin.js`)
- API key
- Built-in agents only (`build`, `plan`)

You can add agents later by re-running the installer with flags.