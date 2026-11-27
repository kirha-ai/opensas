---
name: stat-impl
description: >-
  Implement existing SAS/STAT 15.4 tickets from stat-jira.md with dev subagents,
  SAS reference validation, permanent regressions, and resumable handoff. Use
  for the STAT implementation campaign, not the general jira.md manager loop.
---

# STAT implementation

Coordinate development of the existing `stat-jira.md` backlog. This is a
self-contained workflow: do not invoke or modify `../manager/SKILL.md` to run it.
Keep the general manager's `jira.md` workflow separate. Read `CLAUDE.md` and
the relevant `docs/decisions.md` entries; the STAT-specific rules here override
generic completed-task removal and disposable-worktree conventions.

## Scope and ownership

- Consume only existing tickets in `stat-jira.md`. Do not grow the backlog,
  claim other TODOs, run GitHub intake, or create QA, perf, doc-finder or audit
  agents. The coordinator assigns, reviews and integrates; devs implement.
- Use up to seven dev slots, respecting the actual runtime concurrency limit.
  A finished agent may be closed and resumed to free a slot; preserve its
  worktree and context, and record the queue state. Do not claim seven agents
  are running if the runtime only admitted six.
- Assign one ticket per dev. Give each dev a separate worktree and explicit
  branch, ticket, source scope, reference cases, validation commands and deadline.
  Record ownership before dispatch. Reuse suitable retained worktrees after
  inspecting their state; never reset or remove them as automatic recovery.
- Give independent tasks disjoint write scopes. Coordinate small shared parser,
  dispatcher or rendering edits explicitly. Rebase conflicts belong to the dev;
  preserve both intents, or abort safely and report the conflict.
- Capture the non-protected working branch at startup and recheck it before
  commits, integration and pushes. Never commit/push/merge into main or master.
  Preserve unrelated edits. Do not start a second coordinator for the same tree.
- Keep the session awake with `caffeinate`; retain its process identity and stop
  only that process when the campaign stops. Do not create recurring automations.

## References and acceptance

For every assigned ticket, read its full scope, dependencies and acceptance
criteria. Consult `docs/SAS-STAT-15.4-Users-Guide.pdf` at the cited **one-based
physical PDF pages**, not the printed page numbers.

`tests/STAT15.4-oracle/<ticket>/` is a **temporary read-only baseline** that the
user will delete. When present, read its README, every listed SAS program,
expected output, reference status and relevant log before implementation.
If a migrated folder has already been deleted, use the permanent test mapping
in `stat-jira.md` and the cited specification; do not recreate a second baseline.

Run the original cases unchanged. Check complete outputs, status and diagnostic
semantics, typed datasets/missing fields, and graph identities/data/visuals where
applicable. Execution success, a created file or a rewritten diagnostic program
does not establish acceptance of the original. Preserve the following contracts:

- OpenSAS reports its own current version; it need not copy the SAS build ID.
- Reference `.expected.rc` encodes severity. Check that severity and independently
  enforce OpenSAS's D-009 CLI exit contract; disclose different raw codes/text.
- Whitespace-only normalization must retain all fields in order. Do not drop
  headings, tables or values to pass. Derive per-quantity numerical bounds from
  independent mathematics/specifications, not from observed discrepancies; keep
  the justification executable and disclose where strict equality is false.
- Validate fixed-seed algorithms and sampling layouts where specified. Do not
  substitute a different generator or pin a known wrong stream as a golden.
- Change a permanent expected result only with specific SAS or independent
  evidence and preserved numerical/diagnostic coverage. Never regenerate it
  blindly from OpenSAS. Keep expected corrections separate unless the user
  explicitly requests one combined commit; then explain them in that commit.

## Permanent tests and one state record

Every completed behavior, including the passing part of a DOING or PARK ticket,
must have self-contained corpus fixtures or Zig tests reached by the default
gate. A standalone Python/manual oracle replay is not permanent regression
coverage. Reuse an identical existing test and map all applicable tickets to it
instead of maintaining duplicate expected results.

Before reporting DONE or handing off partial work:

1. Persist the complete input/expected contract in `tests/corpus/`, or use Zig
   tests for typed data, numerical identities/bounds, RNG and plotted coordinates.
   Test assets outside the oracle may be shared by these tests. Preserve the
   strength of the original checks; no untested copies or partial-row substitutes.
2. Remove every runtime read/include of the temporary oracle from permanent
   tests. Record each original case's permanent test path in `stat-jira.md`.
3. Run `zig build gate` and the **separate supplemental suite** required by
   `CLAUDE.md`. Record the exact code SHA, direct process exit and all counts;
   do not treat a successful `tee` or a partial log as a passing test run.
4. Verify the permanent tests with the temporary oracle directory unavailable.
   Temporarily move it outside the checkout with guaranteed restoration on exit,
   then run the gate and supplemental suite. If another worker is using it,
   perform this check in an isolated checkout or coordinate a short read pause.
   Restore it afterward. This is local acceptance, not a change to CI/build rules.

Only `stat-jira.md` holds task status, partial progress, blockers, ownership and
handoff. Keep scientific citations, input provenance and tolerance derivations
beside executable tests. Put temporary outputs in ignored scratch directories.
Never add status documents, implementation-evidence files, validators, actual
outputs, logs or images to `tests/STAT15.4-oracle/`.

DONE means the corresponding reference folder is safe to delete, **not permission
to delete it**. Leave deletion to the user unless explicitly requested. PARK
references remain until their remaining acceptance gaps are resolved.

Do not change `build.zig`, CI/release workflows, the general manager skill or
unrelated configuration merely to enforce this process. Supplemental is a
separate required verification command, not an added default-gate dependency.

## Ticket loop and integration

Use TODO, DOING with an owner, DONE and PARK in `stat-jira.md`. Retain DONE and
PARK entries. A DONE dependency is satisfied even though it remains on the board.

- Time-box each implementation attempt to **45 minutes from assignment**; a
  handoff or steering message does not reset the clock. On expiry or demonstrated
  infeasibility, stop feature work, retain tested partial work, mark PARK with
  exact remaining failures and prerequisites for resuming, and assign another eligible
  existing ticket. Separate a finished implementation's integration queue from
  active work rather than silently extending its implementation clock.
- A missing in-repository feature is a dependency to implement, not by itself a
  reason to PARK. Dispatch its existing ticket. Break validation cycles only
  with an explicit viable interface/contract; do not pretend a stub satisfies
  the original oracle or mark dependent work DONE prematurely.
- Validate source-specific assumptions before changing shared statistical
  kernels; new statistics belong in `src/stat/` under D-029. Unsupported behavior
  must remain visible rather than silently returning plausible results.
- Devs commit only explicit paths and never push. Report branch/base/SHA,
  original-case results, permanent tests, absent-oracle verification and precise
  limitations. Record useful partial regression coverage even on PARK.
- Integrate serially with `git merge --ff-only <dev-branch>`. If the parent tip
  moved, return integration to the dev for a safe rebase and applicable checks.
  A combined batch may share one final gate if all included paths and original
  replays are identified. Never accept red validation or resolve conflicts by
  replacing another dev's work wholesale.
- Only the coordinator pushes the authorized working branch. Mark DONE after
  the verified implementation is integrated and any requested push succeeds.
  Report the tested SHA/counts and remaining limits; do not claim unexercised
  options are supported. If reusing a green receipt, require the same SHA and
  the same required suites/absence check, not just a stale gate marker.
- Refill free slots while eligible work remains and the user has not stopped
  the run. Do not manufacture tickets when the finite board is exhausted.

## Stop and resume

On an explicit stop, stop dispatch immediately and give live devs at most ten
minutes to commit, finish safe in-flight validation and report. Land only ready
verified work within that window; preserve all remaining source, branches,
worktrees and raw evidence. Never force-delete or discard unlanded attempts.

Close all agents, stop the owned `caffeinate`, and record STOPPED plus per-ticket
handoff in `stat-jira.md`: state, tests, exact failures, branch/worktree/tip,
integration status and concrete next steps. No phantom DOING worker may remain;
use TODO for intentionally queued work and PARK for unresolved acceptance gaps.
Keep the required final verification/push results explicit. No automatic resume,
PR creation or merge. A new explicit user request may resume this workflow;
inspect the preserved handoff before reusing worktrees or dispatching tickets.
