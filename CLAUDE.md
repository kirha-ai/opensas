# opensas — house rules (auto-loaded for every agent)

SAS 9.4 interpreter in Zig. You are one agent of a team (up to 7 devs, QA,
manager). Each dev works in its own git worktree (`../opensas-devN`); the
main tree belongs to the manager. For the current STAT campaign, your task comes
only from assigned tickets in `stat-jira.md`; do not consume the legacy board.

## Git — the rules that prevent lost work

- Commit ONLY with an explicit pathspec: `git commit src/foo.zig tests/... -m "..."`.
  NEVER `git add -A`, `git add .`, `git commit -a` — you will sweep a teammate's
  half-done work into your commit (this destroyed work twice).
- Dev/QA/perf/doc-finder agents NEVER push. The manager may push only the current
  human-created working branch; it must never commit or push directly to protected
  `main`/`master`, create/merge a PR, or merge the protected branch. The human
  stops the manager, opens the PR, reviews it, waits for PR CI, and merges manually.
- Commit message format: `<role>: DONE <TASK-ID> — one line` (or `<role>: file <ID> ...`
  when filing). One concern per commit.
- Never rebase/amend/reset pushed history. Divergence → tell the manager.

## Code — house style

- Read `src/lexer.zig` first; match it: `ponytail:` comments for deliberate
  shortcuts, shared `diag.Error` set, arena allocation, case-insensitive SAS names.
- Fail LOUD. For clinical use, silent wrong output is the worst failure class.
  An unsupported feature must error visibly, never no-op. But: fail-loud tests
  assert via the CAPTURED diagnostics reporter — never spawn a real aborting
  process from a test (noise in green runs hides real failures).
- Every non-trivial fix ships a runnable check: a `test` block in the same file
  or a `tests/corpus/*.sas` fixture (+ expected `.txt`). No test frameworks.
- Before touching a shared file, `grep docs/decisions.md` for it — settled
  decisions live there; violating one has caused regressions.

## Definition of done

`zig build gate` green with `tests/STAT15.4-oracle/` absent, permanent regressions
included, tracker updated if the task names one (docs/sas-functions.md
`[x]`, EBNF `(* opensas *)`), committed locally by pathspec. Then STAY RUNNING
and wait for the next task — do not exit.

## Temporary STAT reference baseline

- `tests/STAT15.4-oracle/` is a temporary, read-only reference. The user will
  delete it. Never add status, handoff documents, implementation-evidence files,
  validators, actual outputs or generated images there; never edit its expected
  values to make the interpreter pass.
- Every completed behavior, including a partial DOING/PARK implementation,
  must have persistent `tests/corpus/` fixtures or Zig `test` coverage in the
  default gate. Migrate the input and expected contract before reporting.
  Permanent tests may not read/include files from the temporary baseline.
- DONE additionally requires a case-to-test mapping and verification with the
  temporary baseline unavailable. Preserve full output/status/diagnostic checks,
  typed/missing-field checks and graph/random/numerical checks as applicable;
  do not weaken them to execution-only or a few selected rows.
- Keep task status, partial progress, blockers and handoff only in
  `stat-jira.md`. Keep SAS citations, input provenance and independently derived
  tolerance formulas next to executable tests. Reuse an existing identical test
  instead of maintaining duplicate permanent expected results.
- Do not delete reference folders during implementation unless requested.
  DONE means safe to delete, not permission to delete. When a reference folder
  has already been removed, use the board's permanent test mapping and sources.

## No confidential data in the tree (D-011)

No client name, study identifier, subject data or client-derived program logic
anywhere — code, comments, fixtures or docs. Fixtures use invented data or
published sample data only. When a real-world program motivates a fix, describe
the SHAPE ("an SDTM AE program does X"), never the source.
