---
name: issue-manager
description: >-
  Manager-only workflow for turning GitHub issues into tracked, validated jira.md
  tasks for the opensas SAS interpreter. Use this whenever the manager needs to
  intake, triage, validate, dispatch, or close GitHub issues — e.g. "check the
  open issues", "pull new bugs from GitHub", "any new issues to work on", "triage
  GitHub issue #<N>", "close the fixed issues", or during the manager loop's backlog step.
  Handles the full lifecycle: fetch open issues the human has marked `ready`
  (unlabeled issues are deliberately out of scope), gate each through a reproduce +
  SAS-doc validation step, create confirmed bugs as GH#-tagged tasks in jira.md,
  mark taken issues with the `ongoing` label so they are never pulled twice,
  dispatch to a dev with reproduction instructions, and close issues after their
  green fix is pushed to the remote working branch.
  This skill is for the manager agent only; devs consume the resulting jira.md task.
---

# issue-manager

You are the **manager** of the opensas team (see the `manager` skill). This skill is the
procedure for moving bugs from **GitHub Issues** into the `jira.md` board and back
out again when fixed. The engineering value it protects: a reported bug should
never be dispatched to a dev until someone has **proven it reproduces** and
**confirmed against the SAS 9.4 docs that the expected behavior is actually
correct SAS**. A dev slot is expensive; sending it a phantom bug
(reporter misunderstood SAS) or an un-reproducible one wastes a whole loop and
pollutes the board. The validation gate is the point of this skill — everything
else is bookkeeping around it.

Repo: `kirha-ai/opensas`. All GitHub ops go through `gh`. All board edits obey
the `manager` skill's rules (pathspec commits, completed-task removal).

## The lifecycle at a glance

```
OPEN issue with `ready` label, without `ongoing` label
   │  1. FETCH
   ▼
2. VALIDATION GATE  ── reproduce + check SAS doc ──►  verdict
   │                                                 │
   ├─ CONFIRMED ──► 3. CREATE task in jira.md ──► 4. MARK taken (`ongoing` + comment) ──► 5. DISPATCH to a dev
   │
   ├─ NOT-A-BUG ──► comment with the doc citation, close issue, nothing on the board
   │
   └─ NEEDS-INFO ─► comment asking for a minimal repro, leave open, do NOT label
                                                 │
   fix lands green ──► push working branch ──► 6. CLOSE (close issue w/ branch+commit, swap `ongoing`→`done`, remove task)
```

The numbers are this skill's sections. Run steps 1–5 during the manager skill's
GitHub-issue intake (manager §1 step 5b). Run step 6 — CLOSE (close the issue with
the working branch + commit, then remove the task) — during the manager skill's
verify & merge-gate (manager §1 step 6), after the green fix has been pushed to
the remote working branch.

### Pipeline, don't batch (steps 2→6)

These steps are a **per-issue pipeline**, not global phases. Do NOT validate every
issue, then create every task, then dispatch every dev. The moment a validation
subagent returns **CONFIRMED for one issue**, push *that* issue straight through
create → mark-taken → dispatch → dev **immediately**, while the other issues are
still validating. Each issue flows independently; nothing waits on a sibling.

Concretely, per intake loop:
1. Fetch (step 1) → get the list of new issues.
2. Fire ALL validation subagents at once (step 2, one per issue, parallel).
3. As each verdict lands: `CONFIRMED` → run steps 3+4 for it and dispatch a dev
   (step 5) right then; `NOT-A-BUG`/`NEEDS-INFO` → comment/close per the verdict.
   Dispatch the dev the same turn the task hits the board — a validated task that
   sits at `TODO` for a loop is wasted latency.

The only thing that gates dev dispatch is an open **dependency** (the `manager`
skill's §4): if a confirmed bug genuinely needs another task to land first, leave
it `TODO` with a `[deps: …]` note so it queues — everything else pipelines
through. **Files are NOT a gate.** Two confirmed bugs in the same `src/*.zig`
dispatch to two devs in parallel; the landing protocol (`manager` §7: rebase in
the dev's own worktree, `--ff-only` on the manager side) absorbs the overlap.

---

## 1. Fetch pending issues

Pull open issues that are **cleared for intake** and **not yet taken**. Two labels
govern this:

- **`ready`** — the human's opt-in marker: "this report is worth a dev slot, pull
  it." An issue WITHOUT `ready` is invisible to the manager, no matter how well
  written. This keeps raw inbound reports (questions, duplicates, half-formed
  bugs) out of the pipeline until a human waves them through.
- **`ongoing`** — "Dispatched to jira.md and being worked on", the taken-marker.

So intake is `ready` AND NOT `ongoing`:

```bash
# Human-approved, still open, and not yet pulled into jira.md
gh issue list --state open --label ready --search '-label:ongoing' --json number,title,labels,body
```

Do **not** widen this filter on your own initiative. An unlabeled issue is not
an oversight to be corrected by the manager — it is a human decision not to
work on it yet.

Cross-check against the board as a belt-and-suspenders dedupe — every open issue
already on the board carries its `GH#` id, so an issue whose number already
appears in `jira.md` has been taken even if the label is missing:

```bash
grep -oE 'GH#[0-9]+' jira.md | sort -u
```

If nothing new: say so in one line and fall through to backlog work (§8). An
empty `ready` queue is the normal steady state, not an anomaly. Don't re-triage
taken issues and don't go looking for unlabeled ones.

---

## 2. Validation gate — reproduce & confirm (the important step)

For each new issue, **before it touches the board**, run it through validation.
This is heavier than a glance, so delegate it to a subagent (Agent tool,
`general-purpose`) — one per issue, in parallel when there are several. The
subagent's job is to come back with a verdict and, if confirmed, a runnable repro.

Give the subagent this brief (fill in the issue):

> You are validating a bug report against the opensas SAS 9.4 interpreter before it
> is dispatched to a developer. Do NOT fix anything.
>
> **Issue #<N>:** <title>
> <body>
>
> Do this:
> 1. **Reproduce.** Write the smallest `.sas` program that should exhibit the bug.
>    Build the interpreter (`zig build`) and run it on the program. Capture the
>    ACTUAL output/behavior (values, diagnostics, exit code).
> 2. **Determine expected behavior from SAS 9.4 docs** — do not trust the
>    reporter's claim. Cite the source: the Language Reference: Concepts manual, `docs/sas-functions.md` / the Functions and CALL Routines reference (functions),
>    `docs/sas9.4.ebnf` (grammar), `docs/decisions.md` (settled project decisions).
>    If a doc contradicts the reporter, the doc wins. If the behavior is genuinely
>    ambiguous or undocumented, say so.
> 3. **Verdict**, one of:
>    - `CONFIRMED` — reproduces AND the docs say our output is wrong. Provide: the
>      minimal `.sas`, EXPECTED vs ACTUAL, the doc citation, and the `src/*.zig`
>      file(s) most likely responsible (grep to locate; name the function/line).
>    - `NOT-A-BUG` — either it doesn't reproduce, or the docs say our current
>      behavior is correct SAS. Explain, with the citation.
>    - `NEEDS-INFO` — cannot reproduce from the report and the gap is the report,
>      not the interpreter. Say exactly what's missing.
>
> Return the verdict, the minimal `.sas` (verbatim), EXPECTED vs ACTUAL, the doc
> citation, and the suspected owning file(s). Raw data, not prose.

Fail-loud principle (CLAUDE.md): a bug where the interpreter silently emits wrong
numbers or exits 0 on unsupported input is the worst class — prioritize those.

Act on the verdict:
- **NOT-A-BUG** → comment the finding + citation on the issue, close it, put nothing
  on the board. `gh issue close <N> --comment "..."`.
- **NEEDS-INFO** → comment asking for a minimal repro, leave open, do **not** label
  (so a later loop re-checks it).
- **CONFIRMED** → continue to step 3.

---

## 3. Create the task in jira.md

`jira.md` is ONE flat list — there is no per-source section. Add the confirmed bug
as a line in the board's own format (the spec lives in jira.md's header; match it,
don't invent a variant). The **`GH#<N>` id goes in the source paren** — that is how
step 6 closes the right issue — and the line **embeds the validated reproduction**
so the dev can start immediately without re-triaging:

```
- [TODO] <ID> (GH#<N>, <severity>) — <one-line bug summary>. Repro: <minimal SAS
  one-liner or ref>; EXPECTED <x> vs ACTUAL <y> (SAS doc: <citation>).
  (likely: src/<file>.zig)
```

State starts `TODO`. The `(likely: …)` tail is a **hint**, never a reservation:
the dev decides what it actually changes, and such a hint has pointed at the
wrong file before (D-019).

Keep `jira.md` under ~200 lines (completed-task removal still applies).

---

## 4. Mark taken on GitHub (so it is never pulled twice)

Immediately after the task exists on the board, mark the issue taken. This is what
makes step 1's filter correct on the next loop:

```bash
gh issue edit <N> --add-label ongoing
gh issue comment <N> --body "Tracked in jira.md as GH#<N> ISS-<shortslug> — validated repro attached, dispatched. Will close on fix."
```

Leave `ready` in place — it records that a human approved this issue for intake,
and `ongoing`/`done` already carry the state.

(If a workflow label ever goes missing from the repo, recreate it:
`gh label create ready --color 0e8a16 --description "ready to be handled by our manager"`,
`gh label create ongoing --color fbca04 --description "Dispatched to jira.md and being worked on"`
and `gh label create done --color 7a2cd3 --description "Fixed and closed; the fix is on the working branch"`.
The manager never applies `ready` itself — only the human does.)

---

## 5. Dispatch to a dev

Assign the new `TODO` → `DOING @devN` per the `manager` skill's §4 (deps, load,
critical-path first). Because the task line already carries the
reproduction, expected-vs-actual, and the suspected file, the dev has everything
needed to start. No separate handoff message is required beyond the board.

---

## 6. Close on pushed DONE

During the loop's merge-gate (the `manager` skill's §1 step 6), for any GH#-tagged
task whose fix has landed and whose `zig build test` / `corpus` / `programs` are
green:

1. Keep the task in `jira.md` and the issue open until the fix commit has been
   pushed successfully to the current remote working branch. A local-only commit
   is not closeable because its SHA does not yet exist on GitHub.
2. Close the issue with the working branch and commit reference:

```bash
gh issue close <N> --comment "Fixed on branch <working-branch> in <commit-sha> (<one-line>). Fixture: tests/corpus/<name>. Local suites green: test 0, corpus X/X, programs Y/Y. This branch will be merged through a human-reviewed PR."
```

3. Swap the `ongoing` label for `done` in the same breath. `ongoing` means
   "Dispatched to jira.md and being worked on", which is FALSE once the issue
   is closed, and any label-based view that does not filter by state would
   show closed work as still running; `done` keeps such views truthful in the
   other direction too — a fixed issue reads as fixed, not as unlabeled:

```bash
gh issue edit <N> --remove-label ongoing --add-label done
```

4. Remove the task line from `jira.md` in the same tick. Do not retain a `[DONE]`
   line or copy it to a separate archive; the issue and `git log -p -- jira.md`
   preserve the audit trail.
5. Commit the `jira.md` removal by explicit pathspec and push that board commit to
   the same working branch.

If the fix push fails, do not close the issue or remove the task. If issue
closure fails, likewise leave the task in place and retry/report the GitHub
failure rather than losing the board↔issue link.

---

## 7. Protected-branch, PR, and release boundary

The manager does **none** of the following:

- push or merge directly to `main`/`master`;
- create or merge a pull request;
- create a release or tag.

When the human stops the manager, the manager gates and pushes the current
human-created working branch and reports its branch name, tip SHA, included GH#
issues, and suite counts. The human then opens the PR, reviews it, waits for PR
CI, and merges manually into the protected branch. Fixed issues have already
been closed by step 6 after their green commits became available on the remote
working branch.

If the human later chooses to release, that is a separate human-controlled action
performed manually from GitHub after the merged PR's CI is green.

---

## 8. Never self-stop — the manager loop continues until human handoff

**The manager must never idle-exit while there is backlog.** An empty GitHub-issue
queue is NOT "done" — it means switch to backlog work, not stop. Every loop, in
order:

1. **Intake** (steps 1–6 above): pull `ready` issues, validate, dispatch, and
   close confirmed GitHub issues after their fixes are green and pushed.
2. **If the `ready` queue is empty:** immediately fall through to the classic
   `manager` loop — keep every dev on exactly one live task drawn from the
   backlog (Phase-G grammar gaps, Phase-F functions, corpus-driven failure classes
   §5), and **always nudge/relaunch the QA agent** (lldb + arch-UB sweep, §8 of
   the `manager` skill) — QA-found wrong-output/crash bugs outrank features. There is
   *always* something to improve: a grammar production to implement, a function to
   fill, a corpus class to fix, a bug to hunt, an edge case to explore.
3. **Merge-gate** landed work on a quiescent tree; commit the board by pathspec;
   push only the current non-protected working branch if green; perform the
   protected-branch handoff in §7 when the human stops the manager.
4. **Loop again** — do not stop and wait to be re-invoked unless the human
   explicitly requests the protected-branch handoff in §7. Otherwise, the only
   time you pause is when the tree is green, every dev has a live task, and you are genuinely
   waiting on a completion notification — and even then you resume the moment one
   lands. "Nothing new in GitHub" is never a reason to halt; the backlog is the
   floor of work, not the ceiling.

The user's standing directive: **the manager should always be working** — filling
gaps, exploring, improving — in parallel with whatever is in flight.

---

## Guardrails

- **Never pull an issue the human hasn't marked `ready`** (§1). The label is the
  human's opt-in; its absence is a decision, not an oversight. The manager never
  applies `ready` to an issue itself.
- **Never dispatch an unvalidated issue.** The gate exists because a phantom bug
  burns a whole dev loop. When unsure, verdict is `NEEDS-INFO`, not
  `CONFIRMED`.
- **The docs outrank the reporter.** A confident bug report describing non-SAS
  behavior is `NOT-A-BUG`. Cite the doc every time.
- **One `GH#` id per open issue.** It links board ↔ GitHub; keep it on the task
  until step 6 pushes the green working-branch fix, closes the issue, and removes
  the task. GitHub and the board's Git history preserve the link afterward.
- **Obey manager git rules:** pathspec commits only (`git commit jira.md -m "..."`),
  never `git add -A`, never push a red tree or a protected branch. Commit message:
  `manager: <what> — one line`.
- **Don't touch feature code.** This skill only reads `src/` to write the
  `(likely: …)` hint; the dev writes the fix and picks the files.
- **Human owns PR/merge/release (the protected-branch handoff in §7).** The
  manager may close a fixed issue only after its green fix is pushed to the
  current non-protected working branch.
- **Never idle-exit (the continuous-loop rule in §8).** Empty issue queue →
  switch to backlog + QA and keep looping until the human requests the
  protected-branch handoff.
