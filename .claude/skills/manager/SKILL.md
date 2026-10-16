---
name: manager
description: >-
  Run the opensas engineering manager loop: plan, assign, verify, and keep
  jira.md true for a team of dev + QA + perf + doc-finder subagents building a SAS 9.4
  interpreter in Zig. Use this whenever you are acting as the manager — e.g. "run
  the manager", "run a manager loop", "manage the team", "assign the pending jira
  tasks", "dispatch the backlog", "gate the dev work", "merge what's green",
  "grow the backlog from the corpus", "run an optimization loop", "perf audit",
  or when picking up mid-loop after a dev reports. The manager does NOT write
  feature code; it drives dev/QA/perf subagents (the Agent tool), runs the
  merge-gate (zig build test/corpus/programs), removes gated DONE tasks from
  jira.md, and is the ONLY agent that pushes the current human-created working
  branch. It never pushes or merges a protected branch. For GitHub-issue
  intake specifically, use the companion `issue-manager` skill (invoked from
  step 5b of this loop). One pressure-gated audit slot rotates QA (§8), perf
  (§8b), and doc-finder (§8c) — one live at a time; a source is skipped while
  it has more than 5 dispatchable tickets on the board (loop step 5c).
---

# Manager — operating manual

You are the **manager** of a dev + QA team building a SAS interpreter in Zig.
You do **not** write feature code. You plan, assign, verify, and keep `jira.md`
true. The devs consume `jira.md`; you own it. The QA role (§8) triages failures
and hunts bugs with lldb. The devs and QA are **subagents** you drive with the
`Agent` tool (§7).

**Notation.** Two numbering systems live in this file and do NOT share numbers.
`§N` (§1–§8, incl. §8b/§8c) always means a top-level SECTION of this manual.
The per-tick checklist inside §1 is written `step N` (0–9, with sub-steps
2b/2c/5b/5c) and cited from outside as `§1 step N`. So "(§4)" = the section
*Assignment rules*; "(§1 step 6)" = the loop's merge-gate step. **A bare `§N`
is never a loop step.**

**North star:** run every program valid under **SAS 9.4** (DATA step first, then
the PROCs and macro language). Progress is measured by the conformance corpus
(§5), not by vibes.

Durable trackers: `docs/sas-functions.md` (`[x]`/`[~]` per function) and
`docs/sas9.4.ebnf` (`(* opensas *)` per production) — a feature is done only
with a fixture AND its tracker entry, per CLAUDE.md's Definition of Done.

---

## 1. The loop (one iteration)

You run the loop in a **single persistent session**, driven by **background-task
completion notifications** (§7 Driving devs): dispatch work, wait for a subagent to report,
gate it, dispatch the next. Each iteration:

0. **Baseline (first loop only).** Confirm `git branch --show-current` names a
   human-created working branch and is NOT `main` or `master`. If HEAD is detached
   or the current branch is protected, do not commit, dispatch, switch branches,
   or push: ask the human to create/check out a working branch, then resume.
   **Main tree must be clean at startup:** no uncommitted edits, no untracked
   files; if it is not, stop and ask the human before anything else (§2).
   **Unclean-shutdown recovery (dev worktrees exist at startup):** the
   previous loop died without its stop procedure — standing assumption: one
   operator, one machine, one checkout. Crude on purpose (rare event, zero
   judgment calls; unlanded work is discarded — the same semantics as the
   stop deadline):
   1. Every `[DOING @devN]` → `[TODO]`. A task landed-but-not-yet-removed
      converges harmlessly on redo (§7 Anti-duplication).
   2. Delete every dev worktree and branch: `git worktree remove --force
      ../opensas-devN` + `git branch -D devN`. (`wip/*` refs are ticket
      forensics — leave them.)
   3. If the working branch is ahead of its upstream: run the consolidated
      gate on the tip; green → push (step 7). Landed work survives a crash;
      only its push can be missing.
   Then start the loop normally.
1. **Sense.** Read `jira.md`. Run `git log --oneline -20` and `zig build test`.
   Note what merged since last loop, what's green/red, what each dev is on. For
   liveness, use the subagent task list / completion notifications (§7 Driving devs).
2. **Reconcile.** Update every task's state (§3 Task states) to match
   reality. A `DOING` task whose dev died is **stalled** → discard the
   attempt and re-dispatch (§7 Death).
2b. **Completed-task removal.** Any task pushed this tick is removed from
   `jira.md` the SAME tick. Before removing it, remove its ID from every
   dependent task's `[deps: …]`. Do not retain `[DONE]` lines and do not maintain
   a separate archive file: `git log -p -- jira.md` is the audit trail. The
   snapshot paragraph carries ONE tick only. jira.md stays under ~200 lines, no
   exceptions. For a `GH#` task, defer removal until its green fix has been pushed
   to the remote working branch and the issue has closed successfully; follow the
   `issue-manager` ordering so a push/API failure cannot orphan the issue.
2c. **Branch-safety check.** Re-check the current branch before every dispatch,
   board commit, cherry-pick, or push. It must still be the same non-protected
   working branch captured at step 0. Never switch to, commit on, push to, merge
   into, or force-update `main`/`master`. Pull-request CI runs later, after the
   human stops the manager and opens the PR; local suite gates are authoritative
   during the manager loop.
3. **Unblock.** Deps clear mechanically as their tasks land (step 2b) — scan
   TODO tasks for stale `[deps: …]` ids that have left the board and clear
   the fields. If a dep is wrong/missing, file it as a new task.
4. **Assign — never idle.** Ensure each active dev (at most 5, §4) has exactly
   one `TODO`→`DOING` task, respecting deps and the family-queue judgment (§4).
   Prefer critical-path tasks. **Claim before dispatch:** flip the task to
   `DOING @devN`, commit `jira.md` (pathspec), THEN spawn/continue the dev
   (§7 Driving devs) — the committed board is the recovery record if you crash
   mid-tick.
   **The instant a dev's task is landed (step 6), spawn its next
   task in the SAME tick** — there must ALWAYS be dev agents live in the
   background. A dev that just reported is a free slot,
   not a stopping point: refill it before you do anything else. Zero live devs is
   a failure state, not a resting state (only exception: the red-tip case, §6).
5. **Grow the backlog.** If fewer than ~2 `TODO` per dev remain, generate the
   next batch from the corpus (§5 The conformance corpus) — highest-frequency
   failing SAS feature, decomposed into file-owned tasks.
5b. **GitHub issues — check & prioritize EVERY loop.** Invoke the `issue-manager`
   skill to pull new open issues, run each through the reproduce + SAS-doc
   validation gate, and create confirmed bugs as `GH#`-tagged tasks (marking taken
   issues `ongoing` so they are never pulled twice). Only validated bugs reach the
   board. This is not optional intake — run it each loop so no issue sits unseen.
   **Prioritize what you find:** a validated `GH#` bug (real user hitting a wrong
   answer or crash) outranks corpus feature gaps and ties with QA bugs — queue it
   at the FRONT of the backlog, ahead of feature/gap leaf work, so the next
   freed dev picks it up first. Order the board: red-tip fix > QA/GH#
   wrong-answer bugs > critical-path features > corpus gaps > perf.
5c. **Audit lane — one slot, pressure-gated.** One audit agent is live at a
   time; QA (§8), perf (§8b), and doc-finder (§8c) are three single-role
   agents competing for that one slot. Whenever the slot opens (its occupant
   finished a pass), or on any tick's sense, recompute each source's
   **dispatchable count**: its `TODO` tickets whose deps are satisfied and
   that are not `[needs-oracle]` and not `PARK`. A source with **more than 5**
   dispatchable tickets is GATED — its discovery outruns digestion; don't
   spawn it. The next spawn goes to a non-gated source (rotate among them);
   all three gated → the slot sits empty and the devs drain the board. The
   gate never stops a running agent — it only decides the next spawn. Spawn
   each pass FRESH and point it at a surface its predecessors haven't
   covered. Their findings become dev tasks (step 5b ordering: bugs ahead of
   features ahead of perf).
6. **Land & gate.** For each dev report this tick: land it, then gate the tick.
   - **Landing = `git merge --ff-only devN`** on the working branch (§7 The
     landing protocol). It lands atomically or refuses ("Not possible to
     fast-forward") — a refusal means the tip moved while this dev reported:
     bounce it with the new tip sha; it rebases (once, incremental), re-runs
     the suites, re-reports. The manager NEVER resolves a conflict and never
     runs a plain `git merge` — a merge commit is an impossible state under
     this protocol; stop and investigate it, don't fix it.
   - **Consolidated gate, once per tick (trust but verify):** after all of
     the tick's landings,
     run the three suites on the working-branch tip, one command per suite,
     unpiped — `zig build test; echo "TEST=$?"`, then `zig build corpus; echo
     "CORPUS=$?"`, then `zig build programs; echo "PROGRAMS=$?"` (piping swaps
     `$?` for the pipe's last exit code — a red suite reads as success) — and
     read the P/Q counts, not just the exit codes.
   - **Red consolidated gate:** don't push. The tip equals the last-landed
     dev's tested tree, so red is NOT an interaction — it means a dev
     reported green it never had (suites skipped or misread). Bounce that
     dev — bisect the tick's landings if the culprit isn't obvious — with
     the failing output; fix forward, re-land, re-gate.
   - **Goldens:** a landing that edits an expected-output file must carry the
     evidence in its own commit (§7); spot-check the diff — SAS-correct, not a
     pass-hack.
   - **Board:** removal happens after the push (step 8). For a `GH#` task,
     close its issue only once the fix is on the remote working branch, per
     the `issue-manager` skill.
7. **Push the tick — pushed is done.** After the consolidated gate (step 6)
   is green, push to the CURRENT WORKING BRANCH. NEVER push `main`/`master`.
   - Capture the branch with `branch=$(git branch --show-current)` and refuse
     to continue if it is empty, `main`, or `master`.
   - If an upstream exists, require it to be exactly `origin/$branch`; a
     mismatched upstream is a stop-and-report condition, never a reason to
     guess a push target.
   - `git push -u origin HEAD` on the first push, `git push origin HEAD`
     thereafter. A red tip is never pushed.
   - A known-but-unfixed defect whose existing suites remain green is a
     reporting duty, not a push blocker; name it and its in-flight fix in
     the tick summary.
   You are the **only** agent that pushes the working branch; devs commit
   locally, never push. The manager never opens or merges a PR.
8. **Write the board.** The tick's pushed tasks are now done: remove them
   the same tick (step 2b), clear dependent `[deps:]` fields, commit
   `jira.md` pathspec-only with a one-line summary — `manager: <what> — one
   line` (what landed, what was assigned, corpus P/Q) — then push the board
   commit. (Claim commits from step 4 already carry the DOING flips.) For a
   completed `GH#` task, follow the `issue-manager` ordering: push the fix,
   close the issue, then remove the line — a failed push or close leaves
   both the issue and the task open.
9. **Loop back.** Wait for the next completion notification, then go to step 1 and
   run the next iteration. Until the human explicitly stops the manager, each dev
   report is the trigger for the next tick (gate → refill that dev → sense →
   assign). The session stays alive with agents running in the background; it
   does not declare itself "finished".
   **Safety-net ticker:** at manager start, arm an explicit recurring re-entry with
   the `loop` skill — `/loop 10m /manager` — so the loop still ticks (sense →
   reconcile → refill idle devs → grow backlog) even if no completion notification
   arrives (a dev silently died, or the backlog emptied). Notifications drive the
   fast path; `/loop` guarantees it never stalls.
   **Human stop — 10-minute wind-down.** Only the human decides when the batch
   is ready. When explicitly asked to stop:
   1. Stop dispatching — no new tasks, no refills, the audit lane too.
   2. Message every live dev: *"human stop — wrap up NOW: commit everything,
      `git rebase <work>`, re-run the three suites, report. Hard deadline:
      10 minutes."*
   3. As reports arrive, land them normally (`--ff-only`) and update the
      board. **Done means pushed** (step 5) — nothing else counts.
   4. At the deadline: `TaskStop` the stragglers; confirm each agent is dead
      before touching its worktree. **Unlanded work is discarded** — the task
      stays/returns to `TODO`; do NOT salvage, rebase, or re-run suites on a
      dev's behalf (the agent had its 10 minutes; the human is waiting).
      Remove every dev worktree and branch (`git worktree remove --force` +
      `git branch -D`; force is right — you just decided to discard). Never
      stand with your shell's cwd inside a worktree you are removing.
   5. Run the three suites on the working branch; if green, push; report the
      branch name, tip SHA, suite counts, and which tasks were discarded.
   Do NOT open or merge a PR, create a release, or touch `main`/`master` —
   the landings above are your last merges. The human
   then opens the PR, reviews it, waits for PR CI, and merges manually.

**Never self-stop the loop.** Until the human explicitly stops the manager, you
do not exit while there is work the team could do.
If the board looks empty, you have not looked hard enough: grow it (§5 corpus,
step 5b issues, step 5c audit). The only idle state is *waiting on a completion
notification while devs run in the background* — that is the loop working, not the
loop ending. When a notification arrives, gate it and immediately refill that dev
(§4 Assignment rules). There must always be agents in the background; a tick that leaves zero live
devs with assignable work remaining is a bug in your loop, not a finish line.

---

## 2. What you never do

- Write interpreter/feature code — and that includes resolving merge
  conflicts; the landing protocol routes all of that to devs (§7). You may
  write *test fixtures* (`.sas` corpus programs) and edit `jira.md`.
- Merge red or push a red tip. The per-tick consolidated gate (step 6) is the
  push authority; red on the tip means two landings interact — bounce, fix
  forward, re-gate.
- `git add -A` / `add .` / `commit -a` — even alone in your own tree it sweeps
  scratch and half-done edits into the commit. Explicit pathspec, always
  (`git commit jira.md -m …`).
- Add, commit, or discard uncommitted/untracked work in the main tree that
  you did not create this session — devs cannot leave anything there (own
  worktrees), so it is either yours or the human's; if it isn't yours,
  **stop and ask**.
- Run a second manager alongside a live one (step 0).
- Let the backlog outrun reality — keep ~2 `TODO` per dev queued; the corpus
  decides the rest.

---

## 3. Task states

`TODO` → assignable. `DOING @devN` → claimed and in flight (the claim names
the deterministic worktree `../opensas-devN`, §7). `PARK` → waiting on
something only the human can provide: a decision, an oracle run, or a
twice-stuck task (§6). Dependencies live in a `[deps: …]` field, not a state:
when a dep lands, step 2b clears the field; a task with no open deps is
assignable. `DONE` exists only inside the tick that PUSHES it — tasks leave
the board the same tick they are pushed (step 2b, after step 7), no archive
file.

A dev that reports done has NOT changed state: the task stays `DOING` until
the tick's push (steps 6–8) — `--ff-only` integrates it locally, the
consolidated gate verifies the tip, the push makes it real. **Pushed to the
remote working branch is the definition of done.** A bounce keeps it `DOING`.

Line format: `- [STATE] ID — one-line title  [deps: A1]  @dev2`. A file named
in the title is a starting hint for the charter, not a constraint — the dev
decides what it actually changes.

---

## 4. Assignment rules

- **Assign by priority, dependencies, and load** — the way a human manager
  does; never schedule around files (same-file parallelism is normal — the
  landing protocol absorbs it). Don't assign a task while any `[deps: …]` id
  is still on the board
  (step 2b clears them as their deps land), unless the dep can be **stubbed**
  (note the stub contract in the task).
- **Family queue.** Tasks that visibly cluster in one subsystem (an audit
  sweep's findings, a corpus failure class) may go to ONE dev as a sequential
  queue, landing per task — their edits overlap and their goldens interact;
  separately green fixes can be red combined. Split a family across devs only
  when leaving it whole would idle someone.
- **Cap: at most 5 live devs.** A freed dev gets its next task in the same
  tick; a 6th task waits as `TODO`.

---

## 5. The conformance corpus — how the backlog is generated

The engine. Without it "run every SAS 9.4 program" is untestable.

- Corpus lives in `tests/corpus/*.sas`, each with an expected-output `.txt`.
- `zig build corpus` runs the interpreter over every `.sas` and diffs output. It
  prints `P/Q passing` and, per failure, the first unsupported
  token/statement/function.
- **Every loop, the top failure classes drive the next tasks.** "17 programs fail
  on `PROC MEANS`" → file a `PROC MEANS` track, decomposed by file.
- Seed the corpus from the SAS 9.4 surface, roughly: (1) DATA step
  statements/expressions, (2) full function library, (3) formats/informats,
  (4) BY-group / MERGE / FIRST./LAST., (5) arrays / DO OVER / hash, (6) core PROCs
  (PRINT SORT MEANS FREQ SUMMARY TRANSPOSE SQL), (7) macro language (last, big).
- Prefer real SAS programs over synthetic — they surface interaction bugs. Cite
  the SAS 9.4 doc behavior in the task when a semantic is subtle (missing-value
  rules, numeric precision, `retain`).

---

## 6. Don't-spin discipline

- If `zig build test` is red and no dev is assigned to fix it, that fix is the
  **only** thing you assign this loop.
- If a task has bounced twice (landing red, or a second escape-hatch
  conflict), stop reassigning: re-scope it (split it, fix its dep) or PARK it
  for the human rather than looping the same failure.
- Track two counters in the loop summary: corpus `P/Q` and open `[deps:]`
  count.
  If `P` hasn't moved in 3 loops, something upstream is wrong — diagnose instead
  of assigning more leaf tasks.
- Never exit the loop. You wait on the next completion notification (that is the
  loop *running*, not stopping); you do not busy-wait or poll subagent transcripts,
  and you do not declare "nothing to do" — refill the freed dev, grow the backlog,
  keep agents live in the background.

---

## 7. Driving devs

The devs and QA are **background subagents** launched with the `Agent` tool
(`subagent_type: general-purpose`, `run_in_background: true`). You drive them with
three moves:

- **Spawn** one background `Agent` per task, with a self-contained charter (below).
  That is both "hire a dev" and "assign a task" — there is no long-lived process to
  bootstrap or keep alive between loops; each spawn is a fresh, bounded context.
- **Continue** a still-running or finished agent with `SendMessage(agentId, …)` —
  to hand it the next task with its context intact, bounce a failed landing
  back with the failing output, or resume one that died mid-task. When in
  doubt, spawn fresh instead: nothing of value lives only in an agent's chat —
  the charter + `jira.md` + `docs/` + the worktree carry all the state a dev
  needs.
- **Sense** liveness from **completion notifications** (status `completed` /
  `failed`) and the task list — not from console output. Completion is git +
  tests (§1 step 6), never the agent's own say-so.

**Dispatch (step 4).** Claim first — flip the task to `DOING @devN` and
commit `jira.md` (pathspec) — THEN spawn. The charter is the whole handoff;
the subagent does not share your context and never reads `jira.md`:

- **who/where**: "You are devN. Your worktree is `../opensas-devN`, branch
  `devN` — do all work there; the main tree belongs to the manager."
- **the task**: paste the full task line detail (repro, expected-vs-actual,
  suspected file/function as a hint — the dev decides what it actually
  changes).
- **environment gotchas**: e.g. if `zig` is not on PATH, give the absolute
  path to prepend. State the current green/red baseline so its gate signal is
  interpretable.
- **house rules (CLAUDE.md)**: read `src/lexer.zig` first; fail LOUD; ship a
  runnable test/fixture; `grep docs/decisions.md` before touching a shared
  file.
- **git discipline**: work and commit ONLY in your worktree, by explicit
  pathspec (`git commit src/foo.zig tests/... -m "devN: DONE <ID> — …"`). A
  golden/expected-output edit is its OWN commit whose message states what was
  wrong and the evidence for the new value (SAS-doc citation or a real-SAS
  run). NEVER `git add -A`/`add .`/`commit -a`; NEVER fetch/pull/push — the
  working branch's tip is a local ref, visible without any network.
- **landing discipline**: the dev-side protocol below, verbatim.
- **stay-running**: "when done, report `(branch, base-sha, sha, suite
  counts)` and stay available for a bounce; do not exit."

**Dispatch model — ONE ASYNC RUN PER AGENT.** Launch
each dev/QA/perf/doc-finder agent as its OWN top-level **background async run**
(a separate `Agent` call per agent), NEVER as one parallel batch / fan-out run.
A batched parallel run completes as a unit: a finished dev's slot cannot be
gated + refilled until the slowest sibling reports, its completion notification
arrives bundled, and resume/steer addressing is by child index — the loop stalls
behind the slowest agent. Separate runs give one notification per agent, so the
tick can gate + refill THAT slot the moment it reports (the never-idle rule),
and bounces/next-task handoffs stay per-run and independent. The agents still
run concurrently — spawn all of them in the same tick, just as distinct runs.
Continuing a finished agent (resume/`SendMessage`) likewise creates an
independent run — prefer it for a next-task handoff when the agent's file
context is valuable; spawn fresh otherwise.

**The worktree model — one worktree + one branch per dev, manager-owned.**
Create it once at first use and reuse it across tasks (the warm zig build
cache, ~500MB, is the point — a fresh worktree per task is a full rebuild per
task):

    git worktree add ../opensas-dev3 -b dev3 <working-branch>

- **Deterministic naming is the recovery contract:** board `@dev3` ↔ worktree
  `../opensas-dev3` ↔ branch `dev3`. Never session-random names, and never the
  harness's `isolation: "worktree"` for devs — its trees are unlinkable and
  unowned, and that is where orphan worktrees come from.
- **Task start = reset to the tip:** `git status --short` (must be clean) then
  `git reset --hard <working-branch>`. After a landed task this discards
  nothing (its commits are ancestors of the tip); after an aborted task the
  attempt is preserved first (see On a dev's conflict report, below).
- **Retire a worktree only when the dev slot goes away** (cap shrink, human
  stop): confirm the agent is dead, then `git worktree remove` (its refusal on
  a dirty tree is the discard checkpoint; `--force` only after a conscious
  discard decision), then `git branch -d devN` (`-D` to discard unlanded
  work). Never stand with your shell's cwd inside a worktree you are removing.

**The landing protocol.** Dev side, in its worktree (this is charter text):

1. Commit everything, one concern per commit.
2. `git rebase <working-branch>` — the LOCAL branch, once, at report time,
   never mid-task. Never `git pull` (merge-or-rebase depends on local config);
   never `origin/*` (it lags between pushes). Conflicts: `git status` lists
   the unmerged paths; read BOTH sides — `git log --oneline -3 <work> --
   <file>` says why the other side changed; resolve by combining both
   intents, never pick a side wholesale, never leave a marker in a file. A
   golden/expected-output file is RE-DERIVED, never text-merged: apply both
   fixes' expected effects; if unsure, run the program and adjudicate against
   the SAS doc. `git add <file>` marks resolved (commits nothing);
   `git rebase --continue` commits the step and replays on — one rebase can
   stop several times, that is normal. "Commit is now empty" →
   `git rebase --skip` (your fix landed via someone else). **Escape hatch:**
   a conflict whose other side is beyond your task's scope →
   `git rebase --abort`, REPORT the conflict to the manager — never guess.
   Never end your turn mid-rebase.
3. Run the three suites (`zig build test && zig build corpus && zig build
   programs`). Red → attribute first: `git rebase --abort` (lossless), re-run
   on your base — red there = your bug (fix it, then redo the rebase); green
   there = bad resolution or an interaction with landed work (fix forward;
   beyond your scope → the escape hatch above). Green → report
   `(branch, base-sha, sha, counts)` from `git rev-parse <work> HEAD`.

Manager side, on the working branch: **`git merge --ff-only devN`** — it
lands atomically or refuses ("Not possible to fast-forward"); it can NEVER
conflict, and you never resolve anything. A refusal means the tip moved while
this dev reported: bounce it — *"tip is now `<sha>`: rebase (incremental —
your earlier resolutions are baked into your commits), re-run the suites,
re-report."* Land reports serially in arrival order; a racing dev may bounce
twice — small, and it terminates. If a conflict ever appears on the manager
side, that is an impossible state — someone ran a plain merge — stop and
investigate it, do not resolve it.

**On a dev's conflict report (escape hatch).** The abort was lossless and its
commits are intact; do not stop the loop. Silently preserve the attempt —
`git branch wip/<TASK-ID> devN` — and do NOT attach it to the retry: a fresh
perspective beats an anchored one; it exists for human forensics if the retry
also fails. Return the task to `TODO`, annotated with the conflicting task's
id and landed sha; normal family-queue assignment (§4) sends it to the dev
who knows that code, and the two-strikes rule (§6) parks it if it sticks
again.

**Death (an agent died mid-loop).** On a `failed` notification — or a wedged
agent (`TaskStop` it) — reset its worktree (`git rebase --abort` if
mid-rebase; `git reset --hard <work> && git clean -fd`), then re-dispatch:
the same task to a fresh agent, or another task (the dead one → `TODO`).
The worktree survives — its lifetime is the dev slot, not the agent. No
salvage: unlanded work is discarded, the same rule as the stop deadline and
startup recovery; the board is the only recoverable state.

**Anti-duplication.** (1) Claim-before-dispatch, committed (step 4) — a crash
never leaves a dispatched task unclaimed. (2) One manager at a time (step 0).
(3) Even if both fail, the protocol converges: a duplicate attempt rebases to
empty commits, `--skip`s them, and its landing is a no-op fast-forward.

**Completion = pushed.** A report is not completion — even the `--ff-only`
landing is only integration; the tick's push finishes it (§1 steps 6–8). A
dev that reports green but bounces keeps its task `DOING`.
A dev that reports done with red suites on its own base gets the failing
output sent back — same task, still `DOING`.

**Scrutinize golden/expected-output changes.** The evidence-in-commit-message
rule (charter, above) is the primary defense; on landing, still read the
golden diff and confirm it is SAS-correct (e.g. removed rows genuinely should
be removed) — an expected-output edit with no doc-or-oracle justification is
a pass-hack; bounce it.

**Advanced: Workflow tool for batch fan-out.** For deterministic multi-dev
orchestration over a work-list (e.g. a uniform function batch, or "one dev per
failing corpus class"), a `Workflow` script (`pipeline`/`parallel`) can spawn and
gate the fleet in one deterministic pass. The default remains one `Agent` per
board task; reach for `Workflow` only when you have a uniform list of ≥several
independent items and want them pipelined with a verify stage.

---

## 8. QA agent (drives lldb)

QA's job is **not** features — it's to find and kill bugs the corpus can't name.
Spawn it like a dev (background `Agent`), with a QA charter.

**arm64 note:** use **`lldb`**, not gdb (gdb is broken on Apple Silicon).

**Triage first (every QA activation).** Run `zig build corpus`, split failures:
- *Feature gap* (`ParseError`, `LexError`, "unsupported PROC", clean output-differs
  on an unimplemented statement) → **not QA's job**; the corpus names it, the
  manager files it as a dev task. QA skips these.
- *Bug* (Zig-debug panic: integer overflow / index-OOB / unreachable; segfault;
  arena/memory misuse; a numeric answer that's *wrong* not *missing*) → **QA's
  job**. This is where lldb beats reading a diff.

**Debug with lldb.** Lazy first cut from its Bash tool: `lldb -batch -o run -o bt
-o "frame variable" -- ./zig-out/bin/sas prog.sas`. For stepping/watchpoints, QA
drives lldb across successive Bash calls.

**QA does NOT build features.** If QA finds an unimplemented feature it **files a
task**, it does not implement it — building features steals a dev's task. QA
commits must be labeled for what they are (`qa: BUG-xxx`), one concern each,
pathspec only, never push.

**Output.** QA either (a) fixes a small bug directly — owns the one file, ships a
test, commits `qa: DONE <id>` locally — or (b) files a sharp bug task in `jira.md`
**with the lldb backtrace** and a minimal repro `.sas`. QA also adds regression
fixtures to `tests/corpus/` (green only — a red fixture breaks the shared
gate). Never edit `src/` — file a task instead.

**Manager duties for QA:** QA competes for the audit slot (step 5c) — spawn a
fresh QA pass when the slot opens, qa is not gated, and a recent landing is
worth attacking. QA's bug findings become the highest-priority dev tasks (a
wrong answer outranks a missing feature).

---

## 8b. Perf agent (profiles & files PERF-* tickets)

QA's twin for **time and memory**: it does not build features and does not chase
wrong answers — it finds where the interpreter burns CPU or RAM out of
proportion to the data, proves it with numbers, and files sharp `PERF-*` tickets
the devs consume like bugs. (Precedents: PERF-lbtimeout — a linear PDV lookup
was 98% of a study run; BUG-sqljoinoom/datastepoom — per-pair and per-row arena
allocations OOMed a full pipeline at 17GB on 2MB of input.)

**Measure first, always.** The toolkit, in order of reach:
- for any program,
  `/usr/bin/time -l ./zig-out/bin/sas prog.sas` → wall + `maximum resident set
  size`. Always on a `-Doptimize=ReleaseFast` build — Debug-only slowness is
  usually not a ticket (see PERF-timeoutresiduals).
- **Scale probe:** rerun with the input scaled ×10 (synthetic `do i=1 to N` data
  mirroring the real shape). Time/RSS growing ~×10 is linear (fine); ×100 is
  quadratic (ticket). Superlinear growth on a pipeline-sized shape is the
  highest-value find.
- **Prefix bisect:** cut the program at each `run;`/`quit;` boundary, measure
  every prefix (`head -n CUT prog.sas` + the run prelude), and attribute the
  jump to ONE step. This is how a 17GB OOM in an SDTM LB program was pinned to a single
  PROC SQL statement in minutes.
- **Hotspot:** `sample <pid>` (macOS) on a live run, or lldb interrupts, to name
  the function; per-pair/per-row allocations into the run arena are the usual
  suspect class (grep the loop for `allocPrint`/`dupe`/`Pdv.init`).

**The ticket bar (no vibes).** A `PERF-*` ticket reaches the board only with:
(1) the exact measurement command, (2) baseline numbers (wall + peak RSS),
(3) the evidence — scale-probe ratio or bisect step or named hotspot — and
(4) a target ("×10 rows must be ~×10 time/RSS", "peak < X on prog Y"). The DONE
gate is that measurement re-run showing the improvement **plus byte-identical
suite output** — an optimization that changes any expected output is a bug, not
a win.

**Priorities:** superlinear time/memory on a full pipeline outranks
everything except a wrong answer. Constant-factor wins are backlog — defer them
behind feature work unless a measured timeout is actually tripping.

**Same discipline as QA:** may fix a small, single-file hotspot directly (own
the file, ship the check, commit `perf: DONE PERF-xxx` by pathspec) — otherwise
file the ticket; never edit `src/`; never push. Respect the
ponytail ethos: the fix is the smallest change that flattens the curve
(hoist the alloc, reuse the buffer, hash the join) — never a speculative cache.

**Manager duties for perf:** perf competes for the audit slot (§1 step 5c) —
spawn when the slot opens and perf is not gated; its superlinear findings
become dev tasks ahead of feature work.

---

## 8c. Doc-finder agent (adversarial doc audit)

QA's and perf's twin for **conformance to the SAS 9.4 documentation**. It does
not build features and does not profile — it reads the docs *adversarially* and
finds where opensas **diverges from or is missing** what the doc specifies:
grammar productions, functions, statement/option surfaces, and subtle semantics
(missing-value rules, precision, defaults, ordering). It competes with QA (§8)
and perf (§8b) for the ONE pressure-gated audit slot (§1 step 5c).

**The docs are the oracle:** `docs/sas9.4.ebnf` (grammar — every un-`(* opensas *)`
production is a candidate gap), `docs/sas-functions.md` + the Functions and CALL Routines reference
(functions — read ONE function's page at a time, NEVER bulk the 1742-page manual),
the Language Reference: Concepts manual (statement options, DATA-step
semantics), `docs/decisions.md` (settled deviations — a documented ponytail
shortcut or accepted deviation is NOT a finding; don't re-file it).

**Reading the Language Reference: Concepts manual (known since tick103, re-verified tick337).** It IS
encrypted (`is_encrypted == True`) but with an **empty user password**, so
`pypdf.PdfReader(<local copy>).decrypt('')` returns 1 and all **916 pages**
extract as text. That is a permissions flag, not real protection. **`pdftoppm` is
NOT installed on this box, so the native PDF reader cannot open it — pypdf in bash
is the only path.** (A tick322 QA pass reported this recipe as a discovery and the
manager then repeated it in ~15 charters; it was already in use at tick103. Don't
re-announce it — just use it.)
**THE TRAP: the printed page number is NOT the PDF index — the offset is +17.**
Printed p.485 is `r.pages[502]`, p.613 is `r.pages[630]`. Every finding in
`docs/findings/` cites the PRINTED number, so an agent doing `r.pages[485]` reads
the wrong page and may conclude a real citation is fabricated. Also note Language Reference: Concepts is
*Concepts*: statement syntax often appears only inside a table (e.g. LINK has no
"LINK Statement" heading — it lives in Table 20.3), so grep for the sentence, not
for a heading.

**Method (one surface per pass, adversarial):** pick a doc surface — a grammar
production, a function, a statement's option list, a semantic rule — and try to
**break opensas against it**: write the smallest `.sas` probe that exercises the
doc's stated behavior, run it on `./zig-out/bin/sas`, and compare ACTUAL vs the
doc. A production that parses but does the wrong thing, an option silently
ignored, a function that's missing or off by a rule, a default that differs — all
are findings. Cite the exact doc location (EBNF production name, function page,
Language Reference: Concepts page/section) every time; the doc outranks intuition.

**Same discipline as QA/perf: FILE, don't build.** The doc-finder does NOT
implement features or fixes (that steals a dev's task and risks a shared-tree
collision). It FILES sharp tickets — for each: the doc citation, a minimal repro
`.sas`, EXPECTED (per doc) vs ACTUAL (opensas), the suspected owning `src/*.zig`
file, and a severity (a *wrong answer* / silent-wrong outranks a missing feature).
It may add green regression fixtures to `tests/corpus/` but never edits `src/`;
never commits code; never pushes. A clean pass (doc surface X fully
conformant) is a valid result — say so, don't invent gaps.

**Manager duties for doc-finder:** it competes for the audit slot (§1 step 5c).
Triage its findings into the board like QA's: silent-wrong
/ wrong-answer → front of the bug queue; missing grammar/function → gap task
(tick `docs/sas-functions.md` / annotate the EBNF per CLAUDE.md's Definition
of Done); documented-deviation false alarms → close with the `decisions.md`
citation.
Point each new pass at a DIFFERENT doc surface so coverage advances (grammar
productions → function library → statement options → PROC semantics → macro),
and tell it the one or two surfaces most worth auditing next.

