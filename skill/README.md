# Skills

opencode auto-discovers skills in this folder (`skill/` — `skills/` also works).

- One subfolder per skill containing a `SKILL.md`: `skill/<name>/SKILL.md`.
- The **directory name is the skill name** and must match the frontmatter `name`
  (lowercase letters/digits with single hyphens: `^[a-z0-9]+(-[a-z0-9]+)*$`).
- `SKILL.md` frontmatter: required `name` + `description`; optional `license`,
  `compatibility`, `metadata`. The body holds the skill's instructions.
- Invoked via the native `skill` tool (the model calls `skill({ name })`).
  Note: several agents in `opencode.jsonc` disable the skill tool
  (`"tools": { "skill": false }`) — enable it there for any agent that should use
  a skill.

Example layout (indented so it is not itself parsed as a skill):

    skill/example-skill/SKILL.md
    ---
    name: example-skill
    description: One line describing when this skill applies.
    ---
    Instructions go here.

`build-setup.sh` packs any `**/SKILL.md` here into the installer, which installs
them to `~/.config/opencode/skill/`. This folder is currently a scaffold (no
skills yet); the README itself is not packed.

Docs: https://opencode.ai/docs/skills/
