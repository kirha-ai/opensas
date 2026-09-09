# opensas — house rules (auto-loaded for every agent)

SAS 9.4 interpreter in Zig. You are one agent of a team (3 devs, QA, taste,
manager) sharing ONE working tree. Your task comes from `jira.md` (only lines
tagged with your role).

## Git — the rules that prevent lost work

- Commit ONLY with an explicit pathspec: `git commit src/foo.zig tests/... -m "..."`.
  NEVER `git add -A`, `git add .`, `git commit -a` — you will sweep a teammate's
  half-done work into your commit (this destroyed work twice).
- NEVER push. The manager is the only agent that pushes main.
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

`zig build test` AND `zig build corpus` AND `zig build programs` all green,
fixture included, tracker updated if the task names one (docs/sas-functions.md
`[x]`, EBNF `(* opensas *)`), committed locally by pathspec. Then STAY RUNNING
and wait for the next task — do not exit.

## No confidential data in the tree (D-011)

No client name, study identifier, subject data or client-derived program logic
anywhere — code, comments, fixtures or docs. Fixtures use invented data or
published sample data only. When a real-world program motivates a fix, describe
the SHAPE ("an SDTM AE program does X"), never the source.
