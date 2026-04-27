# prompts/

Prompt packs are how work is delegated to agents in this repo.

A **prompt pack** is a directory under `prompts/` containing:

- An `INDEX.md` describing the workstream, dependency order, parallel safety, and verification commands.
- One `.md` file per task. Each task is **self-contained** and **completable by one agent in one session**.
- Optional `BREAKDOWN.md` with the risk-and-architecture breakdown that motivated the prompt pack.

---

## When to create a prompt pack

Create a new pack when the work is large enough to span multiple tasks, multiple files, or multiple agents. Trivial one-line fixes do not need a pack.

A pack name is `kebab-case` and describes the workstream, not the implementation: `memory-monitor-mvp`, `add-slack-webhook`, `migrate-state-schema-v2`. Pack names should age well — avoid version numbers in the name unless the work is intrinsically tied to a version.

---

## Required format

Every prompt file must include these sections, in this order. See `_template/EXAMPLE_TASK.md` for the canonical shape:

1. **Task** — verb + noun, narrowly scoped.
2. **Context** — why this exists, how it fits.
3. **Required Reading** — exact file paths.
4. **Scope Boundaries** — files that may be modified, files off-limits.
5. **Dependencies** — prompt files that must complete first, or `None`.
6. **Implementation Notes** — enough detail to avoid guessing; not so much that internals are over-prescribed.
7. **Acceptance Criteria** — concrete verifiable checks.
8. **Documentation Requirement** — what docs must be updated, including a `CHANGELOG.md` entry.
9. **Commit Requirement** — independent commit or grouped.

The full rules live in [`AGENTS.md`](../AGENTS.md). When in doubt, that document wins.

---

## INDEX.md format

`INDEX.md` is the table of contents for a pack. It must contain:

- A table with: filename, summary, complexity (Small/Medium/Large), dependencies, target files, verification commands, parallel-safe (Y/N).
- Recommended execution order.
- Which prompts may run in parallel.
- Which prompts must run serially.
- Known risks for the pack as a whole.
- A final verification checklist.

See `_template/INDEX.md` for the canonical shape.

---

## Hard rules

- **No two prompts may modify the same file** unless the dependency order is stated in **both** prompts and in `INDEX.md`. This is enforced by humans and audit agents — there is no tooling.
- **Required reading is required.** An agent that edits without reading will likely violate `CONSISTENCY.md`.
- **Scope boundaries are walls, not suggestions.** If you discover the boundary is wrong, update the prompt and `INDEX.md` first; do not silently overrun.
- **Every behavior change requires a `CHANGELOG.md` entry under today's date.**

---

## Historical packs

Bootstrap and historical milestones are recorded under `prompts/bootstrap/` for traceability. Do not delete completed packs — future agents read them to understand how decisions were made.
