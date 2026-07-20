# Custom tools

opencode auto-discovers custom tools in this folder (`tool/` — `tools/` also works).

- One file per tool: `*.js` or `*.ts`, at the root of this folder (non-recursive).
- The **filename becomes the tool name** (`weather.ts` → tool `weather`). A
  `default` export is named after the file; named exports become
  `<filename>_<export>` (e.g. `math_add`).
- Registration shape:

  ```ts
  import { tool } from "@opencode-ai/plugin"

  export default tool({
    description: "What the tool does (shown to the model)",
    args: {
      // zod-style schema
    },
    async execute(args, ctx) {
      // ctx: { agent, sessionID, messageID, directory, worktree }
      return "result string"
    },
  })
  ```

`build-setup.sh` packs any `*.js`/`*.ts` here into the installer, which installs
them to `~/.config/opencode/tool/`. This folder is currently a scaffold (no tools
yet); the README itself is not packed.

Docs: https://opencode.ai/docs/custom-tools/
