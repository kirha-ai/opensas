---
name: manager-pi
description: >-
  Run the opensas engineering manager loop with DEV work externalized to the
  `pi` harness (Kimi-K3) instead of the in-harness Agent tool. Use this whenever
  you want to act as the manager but offload the code-writing devs to pi — e.g.
  "run manager-pi", "run the manager loop with pi", "dispatch the backlog to
  Kimi", "manage the team using pi devs", "externalize devs to pi". Identical to
  the `manager` skill in every respect EXCEPT one: the dev-dispatch primitive
  (manager §7 Spawn) runs `pi -p` + Kimi-K3 in a git worktree per dev. QA, perf,
  doc-finder, and the manager itself stay Claude. The manager still owns the
  gate, the cherry-pick, and the push.
---

# manager-pi — the manager loop, dev work on pi/Kimi-K3

**Follow the `manager` skill in full** (sense → reconcile → archive → assign →
GitHub intake → audit lane → gate → push → loop; file-ownership, quiescent gate,
don't-spin, never-stop — all inherited). This skill changes **one thing**: devs
are dispatched as `pi`/Kimi-K3 runs in a worktree, not Agents. One-run-per-dev,
completion = git+green (never the agent's say-so), REVIEW bounces, recovery still
apply.

**Stays Claude:** you (manager — gate/cherry-pick/push) and QA/perf/doc-finder.
Only feature/bug-fix devs move to pi.

## Audit lane — all three live, concurrent

perf, doc-finder, QA run in parallel with the pi devs and each other. Relaunch
each the tick it reports, on a fresh surface; never gate a relaunch on a dev
landing. Each writes only its own `docs/findings/<role>-tickN.md` + `tests/corpus/`
fixtures (commit by pathspec) — **GREEN fixtures only**: a RED fixture asserting
not-yet-implemented behavior breaks the shared `zig build corpus` gate every dev
lands against (tick-133); the repro goes in the `.md`, the fixture lands green when
a dev fixes it.

- **File-only while pi devs are live** — never edit a `src/*.zig` a live pi dev owns.
- **Fuzz/probe via the exe → clean-rebuild first** (`rm -rf .zig-cache zig-cache &&
  zig build`); a stale `zig-out` under concurrent worktree builds fakes bugs
  (tick-128). State it in every fuzz-agent charter. (The manager's `zig build` gate
  rebuilds — safe; a bare `./zig-out/bin/sas` is not.)
- **Event-driven once exhausted** — an agent clean ≈3+ runs whose only work left is
  "verify a fix when it lands" stops relaunching every tick; re-arm on its trigger.
  perf (relaunch on a PERF-* landing); doc-finder (tick139); and **QA too as of
  tick148** — surface heavily hardened (corpus ~1208, ~160 fixes), QA self-reported
  low hit rate. All three are now event-driven; the manager's per-landing gate
  (`zig build test/corpus/programs`) is the primary regression net. **Re-arm QA for a
  one-off regression+fuzz sweep every ~4-5 dev landings, on a crash-prone/risky
  change, or when the backlog drains <20** — not every tick. Re-arm perf on a PERF-*
  landing, doc-finder on a new subsystem or <20 backlog.

## Caps & backlog valve

- **≤3 pi devs live** (Kimi 5h quota / 529s). Excess tasks wait as TODO; refill a
  slot only when a dev lands. The Claude audit lane is separate budget.
- **DRAIN MODE — open (TODO+DOING) > 40:** pause perf+doc-finder; QA stays. Add up
  to **2 Claude coder devs** (`Agent`, `general-purpose`, `run_in_background`,
  `isolation: worktree`, same charter) on files no live Kimi dev owns; gate them
  like Kimi devs. Fleet = 3 Kimi + 2 coders + 1 QA.
- **EXIT — open < 20:** re-arm perf/doc-finder; stop spawning coders. (Hysteresis
  40/20 — drain hard, then switch back.)

## Dev-dispatch (replaces manager §7 "Spawn")

Write the task detail to `/tmp/pi-<dev>.txt`, then (Bash, `run_in_background: true`,
ONE call per dev):

```sh
.claude/skills/manager-pi/dispatch-pi.sh <dev> <gated-base-sha> mgrpi-<taskid> /tmp/pi-<dev>.txt [stagger-secs]
```

The script owns all the mechanics: idempotent worktree add, the **role-delta
charter** (embedded — own only your file(s), ship a runnable check, gate green,
commit by pathspec, NEVER `git add -A`/push, report sha+counts; override via
`/tmp/pi-charter.txt`), the `timeout 5400 pi -p -a --provider kimi-coding --model
k3 …` launch (waited on, so you still get a completion notification), and a **wedge
watchdog** that kills the run if no session `.jsonl` appears in 120s. Fan out ≥3
devs with staggered delays (0/25/50/75/100) to dodge the concurrent-init
black-hole. pi auto-reads `CLAUDE.md` (house rules free); you never trust its
report — you re-gate.

## Gate & merge (manager §1 step 6 + cherry-pick)

1. On run exit, `cd` the worktree, run the authoritative gate: `zig build test &&
   corpus && programs`. Red from its own work → REVIEW bounce.
2. Scrutinize any golden/expected-output edit — SAS-correct, not a pass-hack.
3. Green → `git cherry-pick <sha>` onto master, re-gate quiescent master.
4. `git worktree remove` (--force only if nothing ungated). **CONFIRM THE RUN HAS
   EXITED FIRST — "all its commits are on master" is NOT the same as "the run is
   done"** (tick342: I removed a worktree whose pi process was still alive; the
   commits were safe but the run kept working in a directory git no longer tracked,
   so any further commit would have been orphaned). Check
   `ps -eo args | grep mgrpi-<taskid>` before removing.
   **When you do need to stop a run, READ THE TaskStop RESULT** — it echoes the
   command it killed. Same tick, I passed the wrong task id and killed a *productive*
   dev instead of the stale one; it had 0 commits so nothing was lost, but only by
   luck. Map task id → dev before stopping, and re-dispatch immediately if you kill
   the wrong one.
   **Never let your shell's cwd sit inside a worktree you are about to remove** — do
   every inspection with `git -C <worktree> …` from the main tree, never `cd`. Two failures came from
   this (tick326: a board commit landed on the removed worktree's BRANCH and had
   to be recovered from the dangling object; tick329: the persistent shell wedged
   entirely — even `true` returned 1 — because its cwd no longer existed, and only
   absolute-path commands worked after that). **Do NOT push here** —
   pushes are BATCHED per manager §1 step 8 (every 20-30 commits, user directive
   2026-07-25) so each GitHub Actions run covers a batch instead of one landing.
   Check `git rev-list --count origin/master..master` and push only when it
   reaches 20; under that, land locally and say the count in your tick summary.
   The per-landing gate above is unchanged — it, not the push, is the regression
   net.

## Recovery

- **Dead/failed run:** inspect the worktree. Green uncommitted WIP → commit FOR it
  by pathspec (label `… (manager committed after pi mid-run failure)`), cherry-pick.
  Nothing/broken → discard + relaunch. Never mark done unchecked.
- **Slow ≠ dead** — a run can take 30-70 min and edit late; an empty worktree isn't
  "stuck". Judge by worktree edits over time, poll for the commit; don't kill it.
- **The liveness check that actually works** (tick321): `stat` the newest
  `~/.pi/agent/sessions/--home-dev-opensas-pi-<dev>--/*.jsonl` and compare its
  mtime to now. Written in the last few seconds → the dev is working, however
  empty its worktree looks. **`ps` %CPU is NOT a liveness signal: a healthy pi
  run sits at 0.0% because it is blocked on the API**, so 0% CPU + no commit
  looks identical to a wedge and is not one. A big transcript (hundreds of KB)
  with a clean worktree means it is reading/probing — normal for a dev whose
  charter points at a long findings file or a PDF page range.
- **Wedge (session-init black-hole)** — dispatch-pi.sh's watchdog auto-kills it at
  120s. The tell (if you meet one by hand): no `~/.pi/agent/sessions/*<sid>*.jsonl`
  written (TCP to Kimi hung at init, 0 CPU, no error — `pi-retry` can't catch a
  silent hang). `TaskStop` the bg-task (never `pkill`) + relaunch; a fresh
  `--no-session` ping still returns PI_OK, so don't mistake it for an outage.

## Sanity-check pi (once, at loop start)

`pi -p --provider kimi-coding --model k3 --no-session --no-tools "Reply with
exactly: PI_OK"` — non-`PI_OK`/nonzero → auth/model problem; fall back to the plain
`manager` skill and tell the user.
