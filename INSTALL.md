# Installing auto mode on another device

Everything ships in one generated script: `install-auto-mode.sh`.

## Fresh device

```bash
scp install-auto-mode.sh otherhost:
ssh otherhost
GWDG_API_KEY="your-key" bash install-auto-mode.sh    # or run without the env var to be prompted
```

What it does:

1. Checks for `opencode` (also looks in `~/.opencode/bin`); if missing, offers to run the official installer (`curl -fsSL https://opencode.ai/install | bash`).
2. Writes `opencode.jsonc`, `saia-gwdg-plugin.js`, and `prompts/*.md` into `~/.config/opencode/`. Files that would be overwritten are backed up to `~/.config/opencode.bak-<timestamp>/` first; unchanged files are left alone (rerunning is safe).
3. Writes the API key to `~/.local/share/opencode/auth.json` (chmod 600) as `{"saia-gwdg": {"type": "api", "key": "..."}}`, merging into an existing auth.json rather than clobbering other providers. An existing saia-gwdg key is kept unless `--force-key` is passed.
4. Verifies by running `opencode models` and checking that `saia-gwdg/` models are listed (costs 1 request of the shared GWDG rate budget: 30/min, 200/hour per key).

Flags: `--yes`/`-y` auto-accepts prompts (needed for non-interactive use together with `GWDG_API_KEY`), `--force-key` replaces an existing key, `--help` shows usage.

## Maintaining the installer (on this machine)

`install-auto-mode.sh` is **generated** — never edit it directly. After changing `opencode.jsonc`, `saia-gwdg-plugin.js`, or `prompts/*.md`:

```bash
./build-installer.sh    # regenerates install-auto-mode.sh from the live files
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
opencode              # interactive session; Tab until the 'auto' agent is selected
opencode models       # list available GWDG models
```

Subagents: `@coder`, `@researcher`, `@debugger`.
