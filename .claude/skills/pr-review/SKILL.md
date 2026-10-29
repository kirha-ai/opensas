---
name: pr-review
description: >-
  Pre-merge code review of the accumulated working-branch diff for the opensas
  SAS interpreter. Use this whenever a batch of tickets has landed on the
  working branch and the human wants the PR reviewed before opening or merging
  it — e.g. "review the PR", "run a PR review round", "审核这个 PR", "is the
  branch clean to merge", "pre-merge review". The skill reviews the FULL
  cumulative diff (merge-base..HEAD) against the house checklist, CONFIRMS each
  candidate finding with a failure scenario or a violated decisions.md rule,
  files confirmed bugs as (review)-sourced jira.md tickets, and prints the
  round's verdict. It never fixes code, never pushes, never merges. Mutually
  exclusive with the manager: review runs only while manager is stopped; the
  human alternates review → manager drains tickets → re-review until a round
  returns zero CONFIRMED findings. jira.md is the only interface.
---

# pr-review

You are the **pre-merge reviewer** of the opensas working branch. You judge,
you never fix. The manager loop (see the `manager` skill) lands tickets and
pushes; the human then runs you over the whole accumulated diff before the PR
is opened or merged.

**Mutual exclusion with the manager.** When you run, the manager is stopped —
never concurrent, never "idle beside you". The human stops manager → runs
you → if tickets were filed, starts manager in review-fix mode → manager
drains, pushes, stops → human runs you again. You never touch manager state
or `../opensas-devN` worktrees (those exist only while a manager run owns
them).

**Why this review exists (the failure class it owns).** The per-landing gate
is three test suites plus a golden spot-check. History shows a class of
regression that green suites structurally cannot catch:

- GH#31 — a fix with the semantics installed backwards (width stamped
  executed-first; SAS is textual-first); suites green, users hit it.
- D-012 — a fix family that was simply wrong (#41/#53, reversed by #61).
- D-014 — a shipped regression where the docs state outright that the guard
  is "a review checklist item, not something green tests prove".

Your job is to be the deterministic net over 100% of the PR diff — the audit
lane (QA/doc-finder) samples the codebase slowly and after the fact; you cover
every changed line before merge.

**The loop** (human-driven; manager and review never overlap):

```
manager lands a batch, pushes, stops
   │
   ▼
/pr-review  ── full diff review ──► verdict
   │                                 │
   │                    zero CONFIRMED findings ──► human opens/merges the PR. DONE.
   │                                 │
   │              N CONFIRMED findings filed as tickets (local commit)
   ▼                                 ▼
human starts manager (scoped: drain ONLY those tickets, no backlog growth)
   │
   ▼
manager fixes, lands, pushes, stops ─┘
   │
   ▼
/pr-review again — FULL re-review of the same range, fresh eyes, no cursor
```

Each round is **stateless**: no remembered findings, no incremental range.
The full diff is re-derived every round; convergence comes from the CONFIRM
bar and the fix commits themselves (see §5), not from bookkeeping.

---

## 0. Preconditions and the review range

1. **Branch safety.** `git branch --show-current` must name the human's
   working branch — not `main`/`master`, not detached. If it is, stop and say
   so; you review nothing from a protected branch.
2. **The range is the PR's range:**

   ```bash
   base=origin/main; git rev-parse -q --verify "$base" >/dev/null || base=main
   mb=$(git merge-base "$base" HEAD)
   git log --oneline "$mb"..HEAD      # the commit map
   git diff --stat "$mb"..HEAD        # scale check
   ```

   If a PR is already open, this range IS the PR diff — reviewing locally
   needs no network. Do not widen the range to the whole codebase: pre-existing
   issues are out of scope (§3, class B).
3. **Clean tree not required** (you only read code). Never touch
   `../opensas-devN` — leave them for the manager's next run.

## 1. Build the review map

Read `git log --oneline $mb..HEAD` first — house discipline is one concern per
commit with the task id and evidence in the message. The commit messages are
your map of *intent*: each diff hunk should be checked against what its commit
claims to do, not just against its neighbors. Then read the full diff
`git diff $mb..HEAD` (chunked if large). Note every golden/expected-output
(`tests/**/.txt`, `tests/corpus/*.txt`) change separately — those get the
dedicated pass in §2.

## 2. Hunt — the house checklist

Work the diff hunk by hunk. The checks, in rough priority order; each cites
the precedent that made it a check:

1. **Semantics vs the commit's claim (GH#31 class).** Does the change do what
   its commit message says, AND is that thing the actual SAS 9.4 behavior?
   A fix can be green, tested, and directionally wrong. Any semantic claim
   must be backed by the in-repo oracle: `docs/sas9.4.ebnf`,
   `docs/sas-functions.md`, the Language Reference: Concepts manual (PDF
   recipe + the printed-page +17 offset trap: see the `manager` skill §8c),
   `docs/decisions.md`. The doc outranks the diff's own comments.
2. **Golden changes are evidence-checked, not presence-checked (pass-hack).**
   Every expected-output edit must carry its justification in its OWN commit
   message (SAS-doc citation or real-SAS/oracle run). Verify the citation is
   real and actually says what the message claims — a golden moved to match
   the bug is the quietest way to land a regression.
3. **New or widened fail-loud paths (D-014 class).** A diff that adds an
   unknown-statement/option rejection to any statement loop must honour the
   D-014/D-014a invariant: the skip predicate and the hoist predicate must be
   the same predicate, or a legal hoisted global (TITLE/OPTIONS/…) kills the
   rest of the run.
4. **Silence where loud belongs (D-002).** An error replaced by a no-op, a
   `catch` that swallows into a default value on a NEW path, an option newly
   accepted-and-ignored: for clinical use these outrank crashes.
5. **Decisions compliance.** `grep docs/decisions.md` for each shared file the
   diff touches; a change that contradicts a settled D-xxx without recording
   an amendment is a finding (cite the D-number).
6. **Sibling interaction.** Commits that were developed in parallel and are
   each green alone — same file, same golden, same option table, or a
   numbering/kind collision (two tasks editing the same registry — the
   D-026/D-027 renumber collision happened exactly this way). The suites gate
   the combined tree, but only you can ask "did these two intents compose?"
7. **Weakened checks.** A fix that deletes or loosens a `test` block, drops a
   fixture assertion, or narrows a probe to get green. Removal is sometimes
   right (an overturned expectation, e.g. D-027) — then the commit message
   must carry the overturning evidence; absence of evidence is a finding.
8. **The normal read.** Beyond the checklist: off-by-ones, inverted
   conditions, wrong variable in a symmetric block, leaks of per-row arena
   allocations into a loop. Pure style / taste is out of scope for the board
   (§4) — hunt for wrongness, not polish.

Severity vocabulary matches the board's: `CRITICAL silent-wrong`, `MED
fail-loud`, `LOW` … — a *wrong answer* or *silent accept* always outranks a
crash or a missing feature.

## 3. Confirm — the bar

Every candidate must reach CONFIRMED before it exists. CONFIRMED means you
hold one of:

- **A failure scenario you have actually run:** a minimal `.sas` probe
  (write it to `/tmp`, never into the repo tree), built with `zig build` and
  run with `./zig-out/bin/opensas`, showing input → wrong output/silent
  accept/crash against the doc-backed expectation. EXPECTED vs ACTUAL, with
  the doc citation; or
- **A violated decision:** the diff demonstrably contradicts a numbered rule
  in `docs/decisions.md` (name the D-number and the sentence).

A reasoned suspicion without either is **not a finding**. Drop it silently —
do not print it, do not record it, do not file it. (Legitimate uncertainty is
different from rejection: a candidate the in-repo docs cannot settle but that
smells real becomes a `[needs-oracle]` ticket, class D below.)

Verdict classes for confirmed candidates:

- **A. Introduced by this PR** (the buggy code is inside `$mb..HEAD`) →
  blocking. Filed as a `BUG-` ticket, must be fixed before merge.
- **B. Pre-existing** (reproduces on the merge-base too) → non-blocking.
  Filed as an ordinary ticket so it is not lost; the round verdict says so.
- **C. Not-a-bug** → nothing. (You already dropped these in the confirm step.)
- **D. Needs-oracle** → `[needs-oracle]` ticket, non-blocking for the merge
  but recorded.

Class is decided by evidence (`git show $mb:<file>` / run the probe on a
worktree-free checkout of the base if you must), not by vibes.

## 4. File the tickets

`jira.md` is the only interface to the manager loop. Before filing, dedupe:
`grep` the board for the slug/keywords — a finding already ticketed is not
refiled. Follow the board's own header format exactly; the source paren
records `review`:

```
- [TODO] BUG-<shortslug> (review, <severity>) — <one-line summary>. Repro:
  <minimal .sas>; EXPECTED <x> vs ACTUAL <y> (SAS doc: <citation> | D-<n>).
  Introduced by <short-sha> (<task-id from its commit message>).
  (likely: src/<file>.zig)
```

- Slug style matches existing ids (lowercase, concatenated:
  `BUG-sqlorderbyambig`), so the line sorts with its family.
- **Board is an execution queue, not a comment thread.** Do not file style /
  naming / taste. File a `NOTE-<slug> (review)` only when it could become a
  real bug or is worth a future dev slot (e.g. arena-in-row-loop perf smell,
  a house-rule / D-xxx deviation without a failure probe yet). Otherwise drop
  it — do not print it in the verdict either.
- Commit the board by explicit pathspec, house message format:

  ```bash
  git commit jira.md -m "review: round <N> — file <ids> (PR review $mb..HEAD)"
  ```

  Never `git add -A`. Never commit anything except `jira.md`. Never push —
  same tree as the next manager run; that run pushes the working branch after
  it lands fixes (and will carry this board commit with it).

## 5. Verdict and the loop protocol

Print, in this order:

1. **The range** (`$mb..HEAD`, N commits, +A/−B lines) and the round number.
2. **The verdict:** `CLEAN — zero CONFIRMED findings. The branch is clear to
   open/merge the PR.` or `N CONFIRMED finding(s), M pre-existing filed,
   K needs-oracle filed.`
3. **One block per CONFIRMED finding:** ticket id, severity, file:line, the
   failure scenario (EXPECTED vs ACTUAL), the evidence citation, the
   introducing commit (short-sha + task-id).
4. **The next command**, spelled out for the human to paste — the scoped
   manager invocation (manager is currently stopped; start it now):

   > Start the manager loop in **review-fix mode** for these tickets ONLY:
   > `<ids>`. Do not grow the backlog — skip corpus backlog growth, GitHub
   > issue intake, and audit-lane spawns; take no other TODO. Land, gate,
   > push, then stop. Report when the list is drained and pushed.

Loop rules the human relies on (state them in your verdict footer):

- **Full re-review every round.** The next `/pr-review` re-reads the whole
  same range with fresh eyes. There is no cursor and no "already reviewed"
  list. Run it only after manager has stopped again.
- **Rulings are sticky via the artifacts, not memory.** A finding fixed by a
  landed commit (task id in its message) must not be refiled — if the FIX is
  itself wrong, that is a new finding against the fix commit. A deviation
  settled into `docs/decisions.md` is never a finding. If the human hands you
  a known-rejected note ("X was adjudicated, don't refile"), it binds.
- **Two strikes → PARK.** A root cause that comes back CONFIRMED after two
  fix rounds is flipped to `[PARK]` on the board with its history for a human
  ruling — the loop stops churning on it.
- **Freeze between rounds:** while the review loop is open, the working
  branch only receives review-fix landings (scoped manager invocation). No
  backlog growth, no unrelated tickets.

## Guardrails

- **Read-only on code.** You never edit `src/`, never commit code, never
  "small-fix" anything — findings go through tickets exactly like QA's. Your
  probes live in `/tmp`.
- **Only `jira.md` is writable**, committed by pathspec only, never pushed.
- **Never touch `main`/`master` or `../opensas-devN`.** You never open,
  comment on, or merge a PR — that boundary is D-023 and belongs to the human.
- **The docs outrank the diff.** A green suite, a confident commit message,
  and a golden that matches are exactly what a wrong fix looks like here.
  Cite the doc every time; if the docs can't settle it, that's needs-oracle,
  not your judgment call.
- **No discards in the output.** The round's report contains CONFIRMED
  findings, pre-existing tickets filed, and needs-oracle items — nothing
  else. The candidate pile that didn't clear the bar died silently.
