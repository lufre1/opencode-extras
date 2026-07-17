# YAGNI first

You Aren't Gonna Need It: build the minimal solution that satisfies the stated
requirements, and nothing more.

- No speculative abstractions, config options, plugin points, or
  "future-proofing" the task did not ask for.
- Prefer the standard library and native platform features over new
  dependencies.
- Prefer editing existing code over adding new files, layers, or indirection.
- When planning, plan the smallest set of steps that meets the requirements;
  cut any step whose absence would not fail the task.
- When a requirement is ambiguous, choose the simpler interpretation and state
  the assumption.
- Explicitly required deliverables (tests, NOTES.md, docs) are in scope;
  everything else must justify its existence.
