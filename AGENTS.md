# AGENTS.md — Operating Procedure

This is the canonical procedure for **every agent** working in this repository, except the one-time bootstrap agent that initialized the repo.

If you are an agent, read `CLAUDE.md` first, then read this document in full before making any changes. The procedure is deliberately verbose — shortcuts here cause regressions later.

---

## Step 0 — Orient Before Acting

Before making any code changes:

1. **Read all required project documentation.**
   This may include:
   - Project instructions or contributor docs (`CLAUDE.md`)
   - This procedure (`AGENTS.md`)
   - Architecture docs (`ARCHITECTURE.md`)
   - Repository status / roadmap docs (`REPO_STATUS.md`)
   - Consistency / conventions docs (`CONSISTENCY.md`)
   - Any feature-specific guardrail or design docs relevant to the task
   - Any security, permissions, data model, or integration docs relevant to the task
   - The prompt file you have been assigned (under `prompts/<workstream>/`)

2. **Inspect current repository state.**
   - Check the current branch (`git status`)
   - Review recent commits (`git log --oneline -20`)
   - Identify uncommitted, unrelated, or in-progress changes
   - **Do not overwrite, revert, or clean up user changes unless explicitly instructed.**

3. **Restate the intended scope before implementing.**
   - What will change
   - What will not change
   - Which feature areas are affected
   - Any assumptions
   - Any risks or unknowns

If the scope is ambiguous, make the safest reasonable assumption and document it. Ask the user only if the ambiguity could cause data loss, security issues, destructive changes, or major product-direction changes.

---

## Step 1 — Create A Checkpoint

Create a rollback point before starting new work.

1. Review the current diff.
2. Create a checkpoint commit with a descriptive message summarizing the repository's current state.
3. Push the checkpoint commit if a remote exists and permissions allow it.
4. If pushing is not possible, document that clearly and continue with the local checkpoint.
5. If unrelated changes exist, **preserve them**. Do not revert them.

The purpose of this step is to create a clean recovery point before new implementation begins.

---

## Step 2 — Documentation Audit

Audit the required-reading docs and all relevant feature or guardrail docs.

Check for:
- Outdated implementation notes
- Missing feature boundaries
- Missing security or permissions guidance
- Missing data model expectations
- Missing testing expectations
- Missing known limitations
- Ambiguous wording that could confuse a future agent
- Places where docs disagree with the actual code

If docs are incomplete, update them before implementation.

If a new doc is needed, create it. New docs should explain:
- Feature scope
- Data model implications
- Security / permissions implications
- User-facing behavior
- Known limitations
- Testing expectations
- Future work that is intentionally out of scope

Commit and push documentation changes separately with a clear message when practical.

---

## Step 3 — Risk And Architecture Breakdown

Before creating prompts or editing code, produce a short implementation breakdown covering:

1. Feature areas affected
2. Files likely to change
3. Data model changes, if any
4. API / backend / service changes, if any
5. Security / permissions / policy changes, if any
6. Storage or file-handling changes, if any
7. Backward compatibility concerns
8. Migration concerns
9. User-facing edge cases
10. Testing strategy
11. Manual QA checklist
12. Known non-goals

Be especially careful around:
- Authentication and authorization boundaries (n/a for this repo currently)
- Existing persisted data (the local state file under `state/`)
- Existing user workflows (the installed `launchd` agent)
- Notification permission state on macOS

Do not start implementation until this breakdown is clear enough that another agent could continue from it.

---

## Step 4 — Create Prompt Packs

Create a prompt pack under `prompts/<feature_or_workstream_name>/`.

Include an `INDEX.md` and one `.md` file per task. Each task prompt must be **self-contained** and completable by one agent in one session.

Each prompt file must include these sections, in this order:

### Task
A specific, narrowly scoped action using a verb and noun.

### Context
A short explanation of why this task exists and how it fits into the larger work.

### Required Reading
Exact file paths the agent must read before editing. Include:
- Required project docs
- Relevant guardrail docs
- Relevant source files
- Relevant tests
- Relevant configuration, schema, policy, or rules files if applicable

### Scope Boundaries
List exactly which files **may** be modified.
Also list what is off-limits.

> **Hard rule:** No two prompts may modify the same file unless one prompt explicitly depends on the other AND the dependency order is stated in **both** prompts and `INDEX.md`.

### Dependencies
List any prompt files that must complete first. If there are no dependencies, write `None`.

### Implementation Notes
Give enough detail for a competent agent to avoid guessing, but do not over-prescribe internals unless correctness depends on it. Include:
- Existing patterns to follow
- APIs, services, modules, or components likely involved
- Data shape expectations
- Error states to handle
- Backward compatibility concerns

### Acceptance Criteria
Specific checks that prove the task is done. Include applicable items such as:
- Formatting passes (`shfmt -d`)
- Lint passes (`shellcheck`)
- Focused tests pass (`bats tests/<file>.bats`)
- Full test suite passes if blast radius is broad
- Build / install passes, if applicable
- UI / notification behavior verified manually
- Existing data continues to work

### Documentation Requirement
State what docs must be updated, if any. At minimum, explain whether the task requires:
- Updating a guardrail doc
- Updating `REPO_STATUS.md`
- Adding known limitations
- Adding testing notes
- Adding future-work notes
- Adding a dated `CHANGELOG.md` entry **(always required for behavior changes)**

### Commit Requirement
State whether this task should be committed independently or grouped after dependent prompts.

---

## Step 5 — Create `INDEX.md`

The prompt pack must include an `INDEX.md` with a table containing:

- Prompt filename
- Summary
- Complexity estimate: Small, Medium, or Large
- Dependencies
- Target files
- Verification commands
- Whether parallel execution is safe

Also include:
- Recommended execution order
- Which prompts may run in parallel
- Which prompts must run serially
- Known risks
- Final verification checklist

See `prompts/_template/INDEX.md` for the canonical format.

---

## Step 6 — Execute In Dependency Order

Begin implementing prompts in the order defined by `INDEX.md`.

Rules for execution:

1. Agents with no shared dependencies and no overlapping write scopes may run in parallel.
2. Do not allow two agents to modify the same file unless dependency order explicitly allows it.
3. Each agent must follow the required reading in its prompt.
4. Each agent must stay inside its scope boundaries.
5. Each completed prompt should produce:
   - Files changed
   - Tests run
   - Known limitations
   - Follow-up items
6. Integrate agent work carefully.
7. Resolve conflicts by preserving the simpler existing architecture unless the prompt explicitly requires a structural change.

After each logical implementation unit:
- Run focused formatting (`shfmt -w`)
- Run focused tests (`bats tests/<file>.bats`)
- Run linting (`shellcheck scripts/*.sh lib/*.sh`)
- Commit completed work with a descriptive message
- Add a dated entry to `CHANGELOG.md`

Do not batch unrelated changes into a single commit.

---

## Step 7 — Verification

After implementation, run the strongest practical verification set for the blast radius. At minimum:

```sh
# formatting
shfmt -d scripts/ lib/ tests/

# static analysis
shellcheck scripts/*.sh lib/*.sh

# tests
bats tests/

# install smoke test (manual, on real device)
./scripts/install.sh --dry-run
```

If a command cannot be run, document:
- The command
- Why it could not be run
- What residual risk remains

For notification-behavior changes, include a manual QA checklist:
- Trigger a fake "red" pressure event (see `tests/fixtures/`) and confirm a notification fires
- Confirm debounce works (no second notification within the cooldown window)
- Confirm "recovered" notification fires when pressure returns to normal (if implemented)
- Verify no notification fires under nominal load

---

## Step 8 — Launch Audit Agents

After implementation and initial verification, launch separate audit agents.

Use separate agents for distinct review concerns:

1. **Code correctness audit** — bugs, regressions, bad assumptions, fragile parsing of `memory_pressure`/`vm_stat` output, missing tests.
2. **Security / permissions audit** — `launchd` plist permissions, state file permissions, log file permissions, unsafe `eval`/word-splitting in shell.
3. **Product / UX audit** — notification copy, debounce behavior, install/uninstall ergonomics, idempotency.
4. **Documentation / prompt audit** — whether docs, guardrails, prompt packs, and `REPO_STATUS.md` match the final implementation.

Auditors should be adversarial and specific. Each audit must report:
- Findings ordered by severity
- Exact files or areas involved
- Whether each finding is blocking or non-blocking
- Recommended fix
- Missing tests or manual QA
- **Residual risk even if no findings are reported**

Do not treat "no findings" as proof of correctness.

---

## Step 9 — Fix Audit Findings

Review audit findings and classify each one:
- Must fix before final
- Should fix now if low-risk
- Document as follow-up
- Invalid or intentionally out of scope

Fix all blocking findings. After fixes:
- Run relevant tests again
- Run lint / analysis again
- Update docs if behavior changed
- Add a dated `CHANGELOG.md` entry for the fix
- Commit and push fixes separately when practical

---

## Step 10 — Final Report

When complete, report:

1. Commits created (and pushed, if a remote exists)
2. Prompt packs created
3. Major files changed
4. Verification commands run and results
5. Audit agents launched and their findings
6. Fixes made from audit findings
7. Known limitations
8. Recommended next steps

Be direct about remaining risk. **Do not imply the work is production-ready unless tests, permissions, docs, and manual QA support that claim.**

---

## Always

- All work must be documented in `CHANGELOG.md` under the current date. Create a date heading if one does not exist.
- Quote shell paths. The repo path contains spaces.
- Use bash 3.2-compatible constructs only.
- When in doubt, narrow scope.
