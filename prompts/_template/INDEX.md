# INDEX — &lt;workstream-name&gt;

> Replace `<workstream-name>` with the kebab-case directory name. Delete this quote line.

## Summary

One paragraph describing the workstream's user-visible outcome and why it exists.

## Tasks

| File | Summary | Complexity | Depends on | Target files | Verification | Parallel-safe |
| --- | --- | --- | --- | --- | --- | --- |
| `01-do-the-first-thing.md` | First action | Small | None | `lib/foo.sh`, `tests/foo_test.bats` | `make check` | Yes |
| `02-do-the-second-thing.md` | Second action | Medium | `01-do-the-first-thing.md` | `lib/bar.sh`, `tests/bar_test.bats` | `make check` | No |

## Recommended execution order

1. `01-do-the-first-thing.md`
2. `02-do-the-second-thing.md` (after #1)

## Parallelism

- Prompts that may run in parallel: _list pairs/groups, or "none"_.
- Prompts that must run serially: _list dependency edges_.

## Known risks

- _Risk 1 with mitigation._
- _Risk 2 with mitigation._

## Final verification checklist

- [ ] `make fmt-check` passes
- [ ] `make lint` passes
- [ ] `make test` passes
- [ ] Manual install/uninstall smoke test (if scripts changed)
- [ ] `REPO_STATUS.md` updated if behavior changed
- [ ] `CHANGELOG.md` has a dated entry
