# decisions.md — settled design decisions (ADR-lite, one line each)

Grep this before touching a shared file. Manager appends when a reconcile
settles something; devs may propose but the manager merges. Violating one of
these caused real regressions (see D-001).

- D-001 `writeCsv` (io.zig) is SHARED by PROC EXPORT and the libname TARGET
  engine — scope any behavior change to the caller, never the shared writer
  (BUG-csvregress broke 18 programs by editing the writer for one caller).
- D-002 Fail-loud policy: an unsupported statement/PROC/feature errors visibly
  and non-zero; silent no-op is forbidden (clinical: silent success is the
  dangerous failure).
- D-003 Negative tests exercise error paths via the captured diagnostics
  reporter, never a real `process.exit`/abort child (TEST-quietnoise, twice).
- D-004 Macro expansion INTERLEAVES with execution: flush-and-execute at
  `run;`/`quit;` boundaries so CALL SYMPUT feeds later `%do` in the same body
  (BUG-macrointerleave — this took studybench 0/27 → 26/27).
- D-005 `writeLibOutputs` never writes `member.csv` where a binary source
  (`member.xpt`/`.sas7bdat`) exists in the same dir — a CSV shadow silently
  bypasses the binary readers on the next run (BUG-csvshadow).
- D-006 Hermetic suites (unit/corpus/programs) live in `zig build`; env-heavy
  acceptance benches (study data, absolute paths, minutes) live in `scripts/`.
  Every bench-found interpreter bug gets distilled into a committed fixture.
- D-007 Bench verdicts gate on OBS COUNT before PROC COMPARE — "No unequal
  values" on 0 common obs is a false pass (BUG-studybench-falsepass).
- D-008 File I/O uses portable `std.fs` (cwd().createFile/openFile), never raw
  `std.posix.openat`/`AT.FDCWD` — Windows target has no posix AT layer
  (BUG: BUILD-windows).
- D-009 Exit-code contract (FLY-exitcodes): 0 = clean run; 1 = user-program
  error (their SAS code is wrong: parse/exec/data errors in valid-SAS terms);
  2 = opensas defect or gap (UNSUPPORTED feature, internal panic). Downstream
  agents route on this: rc=1 → fix your SAS; rc=2 → file an opensas issue.
- D-009b **THE TWO REDUCTIOS THAT DECIDE A BORDERLINE rc** (amended 2026-07-29
  tick396x by the manager, on a proposal @coder-d9 correctly declined to make
  itself). Both directions of the 1-vs-2 question kept getting re-argued, so
  both are now settled here rather than per-ticket:
  (i) **A gap stays rc=2 even though real SAS runs the program clean.** Every
  gap is BY CONSTRUCTION valid SAS that real SAS accepts, so "but SAS exits 0
  here" cannot downgrade one — if it could, rc=2 would be unreachable and the
  contract meaningless. Settled at 321b444e.
  (ii) **A user error stays rc=1 even when opensas might have misdetected it.**
  Whether OUR detection is right is a separate bug; the rc reports the CLASS the
  condition belongs to in real-SAS terms, not our confidence in spotting it.
  Without (ii), every rc-1 verdict in `docs/findings/audit-exitcodecontract.md`
  can be re-opened indefinitely.
  Corollary, from 2a57cc33: when two sites emit the SAME SAS ERROR TEXT with
  different rcs, that is settled by internal consistency alone — no citation
  needed, the tree has already voted.
- D-009a **ABORT is an EXCEPTION to D-009 and propagates its own rc** (amended
  2026-07-27 tick359, manager-verified by probe, not by report). `abort abend 4`
  exits **4** and `abort return 3` exits **3** — the user-supplied return code
  becomes the process exit code, SAS-batch-like, so an ABORT rc is NOT confined
  to the 0/1/2 set. A downstream agent routing on D-009 must treat an exit code
  outside {0,1,2} as "the SAS program chose this rc", not as an opensas defect.
  History worth keeping: the EBNF's `abort_stmt` note asserted the OPPOSITE
  ("the rc is surfaced in the log message, not propagated to the process exit
  (D-009)") and that claim was **stale** — the tick356 EBNF audit caught it by
  probing and corrected the note in 9be19dba. I re-ran the probes here before
  amending, because replacing one unverified claim with another is how this
  file stops being trustworthy.
  **PRECONDITION, added 2026-07-29 tick400 from QA's cross-landing rc sweep
  (F1): ABORT OUTRANKS EVERYTHING IT REACHES — and only what it reaches.** An
  `abort return 3` propagates its rc only if its step actually RUNS. Any earlier
  step error puts the run into syntax-check mode (BUG-errhalt), which SKIPS every
  later step, so the ABORT never executes and the process exits with the earlier
  error's rc instead: `proc print; run;` (no dataset — a user error) followed by
  `data _null_; abort return 3; run;` exits **1, not 3**. This is not a defect and
  it predates the rc epic — a `proc means` error did the same at baseline — but
  D-009a as written promises the ABORT rc unconditionally, and a downstream agent
  routing on exit codes needs to know the promise is conditional on reachability.
  STILL OPEN, filed as DEC-abortrcvsD009: the same audit found **gap exit codes
  are inconsistent (1 vs 2)** — D-009 says a gap is 2, and some gaps exit 1.
  That is a conformance bug against our own contract, not a doc problem; it
  needs a dev pass to make every gap path agree.
- D-010 The board carries OPEN work only; DONE lines move to jira-archive.md
  the same tick; snapshot = one tick (AGT-archive/AGT-ticklog).
- D-011 **NO CONFIDENTIAL DATA IN THE TREE** (user decision 2026-08-17, at
  open-sourcing; supersedes the old "repo stays private" ruling). No client
  name, study identifier, subject data or client-derived program logic anywhere
  in the repo — code, comments, fixtures, docs or board. Fixtures use invented
  or published sample data only. When a real program motivates a fix, record
  its SHAPE ("an SDTM AE program does X"), not its source. Historical board
  prose is redacted to neutral placeholders (`sponsor`, `STUDY-01`) rather
  than deleted.
- D-012 PROC SQL DELETE `*` (2026-07-09, #61 REVERSES #41/#53 which were WRONG):
  SAS 9.4 leniently ignores a stray `*` in DELETE and executes it — treat
  `DELETE * FROM t` as `DELETE FROM t` (emit a non-fatal note). Proof: a real
  SDTM LB program golden. The prior fail-loud MSG-sqldeletestar (caa5113) is
  removed. Exception to D-002 fail-loud: real SAS accepts this, so we must too.
- D-013 Chained comparison `x < y < z` = `(x<y) and (y<z)` (2026-07-23, doc-finder
  tick216 + Language Reference: Concepts p.136 Table 6.6 fn.8: "An exception... when two comparison
  operators surround a quantity... x<y<z is evaluated as (x<y) and (y<z)").
  opensas's AND-chaining (parser_expr.zig:236-248 + chained_cmp fixture) is
  CONFORMANT SAS 9.4 — NOT a non-conformant extension. BUG-chainedcmp's premise
  (that SAS is left-assoc `(5>4)>3`=0) was WRONG; the "arbitration" is resolved:
  keep AND-chaining, do not flip to left-assoc. Verified `5>4>3`→1.
- D-014 A PROC statement-loop fail-loud MUST skip hoisted global statements
  (2026-07-25, QA tick284 F1 — BUG-transposeglobalstmt, a shipped REGRESSION):
  `main.zig:807-826` hoists a mid-step TITLE/FOOTNOTE/OPTIONS/ODS/LIBNAME/FILENAME
  to its own global segment but deliberately LEAVES ITS TOKENS in the step,
  documented there as harmlessly skipped. So any PROC whose statement loop gains
  a D-002 fail-loud on unknown statements MUST first skip a
  `parser.isGlobalKw(tok.text)` statement to its semicolon — otherwise a legal
  `proc x; title "t"; ...` becomes a hard ERROR, and because a step ERROR triggers
  syntax-check mode (BUG-errhalt) it then skips EVERY LATER STEP of the program.
  One legal TITLE silently kills the run. This bit TRANSPOSE (471645f, fixed
  61de2c7) and COMPARE (pre-existing, same commit). The per-landing suite gate does
  NOT catch it — no fixture used a mid-step global inside a PROC — so the guard is a
  review checklist item, not something green tests prove. When adding a fail-loud
  statement loop to any remaining PROC, add the isGlobalKw arm in the same commit.
- D-014a AMENDMENT to D-014 (2026-07-25, QA tick290 F5 — QA's critique of D-014 is
  CORRECT and this supersedes the narrow wording): D-014 said a PROC statement-loop
  fail-loud must skip `parser.isGlobalKw`. **The real invariant is that the SKIP
  predicate and the HOIST predicate must be the SAME predicate.** They are not:
  `parser.isGlobalKw` (the skip) covers `ods`/`libname`/`filename`, while
  `main.isMidStepGlobal` (the hoist) does not. So satisfying D-014 as literally
  written traded a hard ERROR for a SILENT NO-OP: an in-step `ods`/`filename` is now
  skipped by the PROC loop but never hoisted to a global segment, i.e. it does
  nothing at all, quietly. (LIBNAME survives only by accident, via the separate
  `parseLibnames` pre-pass.) That is a worse failure class than the over-strict
  error D-014 was written to fix. **Rule: when adding a skip arm, skip exactly what
  the hoist actually handles — or widen the hoist in the same commit.** Whichever
  side you change, the two predicates must be brought back into agreement, ideally
  by having one call the other rather than duplicating a keyword list. Tracked as
  GAP-globalpredicatemismatch.

- D-022 **X AND `ODS <destination>` ARE INERT BY DESIGN — AND THE TWO THAT ARE
  OBSERVABLE FROM OUTSIDE THE SESSION CARRY A NOTE, SO D-002 HAS AN EXPLICIT
  CARVE-OUT INSTEAD OF AN IMPLICIT ONE** (2026-08-26, GH#83 part 1
  BUG-xstmtsilentnoop; the entry `jira.md`'s Phase-G holdout audit asked for, so
  these stop reading as debt forever). Two separate rulings, one entry:
  (a) **INERTNESS, SETTLED, NOT DEBT.** `X 'command';` parses and does NOT run
  the OS command, and an `ODS <destination>` statement is accepted as a listing
  no-op (opensas renders ONE output stream; ODS OUTPUT/SELECT/EXCLUDE/TRACE stay
  LOUD by name). Neither is an unimplemented gap waiting for a dev — both are
  deliberate, and `docs/sas9.4.ebnf` deliberately withholds `(* opensas *)` from
  `x_stmt`/`ods_stmt` to say so. Do not "finish" them.
  (b) **BUT INERT MUST NOT MEAN SILENT.** `isInertGlobalKw`'s doc-comment
  justifies the whole set as *"Real SAS global statements a batch interpreter
  cannot observe"*. That justification is TRUE for RUN/QUIT, GOPTIONS, SASFILE,
  PAGE/SKIP and DM's windowing commands (clear, editor, output-window), and it is
  **FALSE for exactly two**, which therefore emit a NOTE:
  **X** — the side effect is on the FILESYSTEM, outside the session
  (`data _null_; x "mkdir /tmp/d"; run;` gave zero output at rc 0 and no
  directory), and **DM with a FILE/OUT command** — log/output redirection, where
  the user's downstream log check reads a file nobody wrote. Silence there is a
  D-002 violation of the exact **D-014a** shape: satisfying a rule as literally
  written traded a loud failure for a SILENT NO-OP, "a worse failure class than
  the over-strict error D-014 was written to fix".
  **A NOTE, NEVER AN ERROR — this is the load-bearing half.** An ERROR would
  errhalt (BUG-errhalt) and skip EVERY LATER STEP of any program that
  legitimately contains an X statement: one legal statement kills the run, which
  is precisely D-014. The rc must not move. Corollary for anyone widening this:
  note only what is observable — a substring match on "out" would have noted the
  commonest DM idiom in the corpus (`dm 'log;clear;output;clear'`, whose "output"
  is the OUTPUT WINDOW) for nothing, so the predicate matches WHOLE WORDS.
  **RESIDUAL, deliberately left (main.zig is another owner's, GH#83 part 2):**
  the NOTE fires at the MID-STEP sites only (`parser.zig` noteUnexecuted, from
  parseProgram's global swallow and parseStmtRaw's x/dm arm). A TRUE OPEN-CODE
  `x "…";` / `dm log "file …";` — i.e. one that follows a completed step — is
  segmented by `main.zig` (`isXStmt` :1142 → handleGlobal, `isInertGlobalKw`
  :1148) and STILL EXITS SILENT. Probed both ways, not assumed (D-021): a
  standalone file with no step falls into the anonymous `data _null_` fallback
  and DOES note, which is why this needs saying. GH#83 part 2 already holds
  main.zig for the open-code-vs-mid-step recognizer split — the open-code NOTE
  belongs in that pass, calling the same emitter. Until then
  `tests/corpus/open_code_stmt_allowlist` is UNCHANGED and correct: it exercises
  the open-code path only.
- D-015 A FUNCTION ABSENT FROM THE SAS 9.4 REFERENCE MUST NOT BE IMPLEMENTED, even if
  it exists in a later SAS product (Viya) — keep it LOUD (2026-07-25, tick346, adjudicating
  a direct disagreement between two devs on GAP-weekufn):
  `@pi-ff` scanned the full 1742-page *Functions and CALL Routines Reference*, found no
  WEEKU/WEEKW function entries, and resolved the ticket as documented-loud. `@pi-ff2`
  then IMPLEMENTED them, justifying it as "the Viya function names" while conceding in
  the same commit message that the 9.4 funcref ships only the `WEEKUw.`/`WEEKWw.`
  FORMATS. **Manager verification:** WEEKU/WEEKW occur on exactly TWO pages of that
  PDF, both inside the WEEK Function's "See Also" list under the headings `Formats:`
  and `Informats:`, cross-referencing *SAS Formats and Informats: Reference*; the
  string "WEEKU Function" appears nowhere. The dictionary jumps WEEK -> WEEKDAY.
  **Ruling: ff is right, ff2's commit was NOT taken.** The reasoning generalizes:
  implementing a nonexistent function is a SILENT SUPERSET — a program with a typo or a
  Viya-only call computes a plausible number where real SAS 9.4 errors
  "The function WEEKU is unknown". That is the same failure class as accepting the
  nonexistent NEGPAREN informat (tick245 #14), which this project deliberately made
  loud. The north star is SAS **9.4**; a later product's surface is not evidence.
  Corollary for the EBNF/function trackers: do NOT tick `[x]` for such a function.

- D-021 **A LOUD GUARD PROVES NOTHING UNLESS SOMETHING REACHES IT — AND TWO BUGS CAN
  CONCEAL EACH OTHER** (2026-07-29 tick426, generalised by the manager after the same
  shape appeared FOUR times in one session). The pattern: a guard exists, is correct,
  and is never executed, so the suite is green and the defect it was written for is
  live.
  - `BUG-hashofhashexplicit`: the nested-hash guard lived inside `collectArgs`, which
    two of the three producers never call — and a THIRD producer (the `dataset:` bulk
    load) never reached argument collection at all.
  - `BUG-declaredobjnamevalue`: the fix at the general expression point still left
    `put h;` fabricating a missing, because a PUT item is an `ast.PutItem` and never
    reaches eval.
  - `REVERT-infileendmultirec`: deleting the multi-record clause left the suite FULLY
    GREEN, because every END= fixture reads DATALINES and is caught by the instream
    clause first — half the guard was dead as far as the tests could tell.
  - `BUG-pointredefinesnobs`, the sharpest case: `set a b point=p;` DOES raise a loud
    error at p=4 — but the canonical idiom takes its loop bound from `nobs=`, and the
    under-reported count meant the loop stopped at 3 and **never reached the guard**.
    Result: 3 of 5 observations, exit 0, no diagnostic. **The under-count made the
    guard unreachable and the guard's existence made the under-count look harmless.**
  Practical rules. (1) When you add a guard, name the producers that reach it and
  check EACH — "the other path fails loud" is a claim to verify, not to assume; a
  comment asserting it has been wrong here. (2) **A mutation that fails to redden is a
  FINDING**: it means no test drives that path, so delete the code and see what
  survives before believing the coverage. (3) When two defects are filed on one
  statement, probe them SEPARATELY before fixing either — the compound can be silent
  while each half alone is loud.
- D-020 **THE PAGE-MARKER RULE IS NOT "THE NUMBER BEFORE THE MARKER" — IT IS THE
  VOLUME'S STATED OFFSET** (2026-07-29 tick415, from @coder-f4, after SEVEN
  off-by-one page corrections in one session). The habit everyone learned here is
  "a page FOOTER belongs to the PRECEDING page, so the number just above the
  `=== pdf N ===` marker is the previous page". That is right for seven of the eight
  volumes and **WRONG for the Statistical Procedures volume**, which carries
  its page number in a **RUNNING HEADER**: the number *follows* its marker and
  belongs to *that* page (`=== pdf 411 ===` then `408 ! Chapter 4: The UNIVARIATE
  Procedure`, offset **+3**, so 411-3 = 408 ✓). Its provenance header says both
  facts outright. **So the position heuristic reverses per volume and the only
  check that always works is arithmetic: nearest marker minus THAT VOLUME'S stated
  offset, then confirm against the printed number wherever it sits.** Offsets seen
  so far: Procedures Guide +49, Statements Ref +11, Formats/Informats +13, Macro
  Ref +15, SQL User's Guide +15, statistical +3. Treat a page number quoted by
  another agent — even a verified one — as unverified: two agents re-checked a
  colleague's verified page tonight and both found it off by one.
  **AMENDMENT (tick423, @coder-mo): THE OFFSET ITSELF CAN BE OFF BY ONE, because
  some extractors index PDF pages from ZERO.** Language Reference: Concepts' stated +18 gives pdf 535 for
  printed p.517, but the text sits under `=== pdf 534 ===` — pdf 535's footer reads
  `518 Chapter 21`. The printed number was right and the arithmetic was right; the
  BASE was 0. So the final authority is always **the printed number visible on the
  page you are quoting**, not the marker and not the offset — use the arithmetic to
  FIND the page and the printed number to CONFIRM it. This is the fourth distinct
  species of citation error tonight (wrong page, wrong volume, wrong site, wrong
  vintage — now wrong INDEX BASE) and the second that no amount of footer-versus-
  header care would catch.
- D-019 **REPRODUCE BEFORE YOU DISPATCH — AN ID GREP IS NOT ENOUGH** (2026-07-29
  tick410, after SIX stale board lines in one session, one batch that was 100%
  stale, and two double-dispatches earlier in the week). The existing pre-dispatch
  check is: grep `jira-archive.md` and `git log` for the ticket ID. **That check
  passes cleanly on an already-fixed ticket**, because a fix often lands under a
  DIFFERENT id — the dev finds the real root, names it after that, and the
  originating line is never closed. All five tickets in the tick306 exec batch
  greped clean and all five were already fixed by later landings. So the rule is:
  **for any ticket older than roughly ten landings, RUN ITS REPRO on a
  clean-rebuilt binary before writing the charter.** It costs one build; a wrong
  dispatch costs a 30-60 minute dev slot and, worse, produces a confident dev
  hunting a bug that is not there. Corollary observed the same tick: a stale
  ticket's `[owns:]` line is stale too — BUG-hashattrput named exec.zig and the
  actual fix had to live in parser.zig, so an ownership reservation made from an
  old line can lock the wrong file. Related: `[[verify-backlog-todo-before-dispatch]]`.
- D-018 **CLOSING A CATCH-ALL: REMOVE FROM THE GAP ARM ONLY WHERE THE DOC
  *EXCLUDES* THE VALUE — A VALUE THE DOC MERELY FAILS TO MENTION IS KEPT AND
  RECORDED** (2026-07-29 tick404, from @coder-f4, who needed this rule to tell
  QA's F2 apart from its own TEMP/DDE case and found the ticket had not given it
  one). The rc epic splits catch-alls so a documented-but-unimplemented value
  exits 2 ("file an opensas issue") and a typo exits 1 ("fix your SAS"). Deciding
  membership needs an asymmetry rule, because the two errors do not cost the same:
  **keeping a possibly-bogus name at rc 2 costs one spurious "file an issue";
  dropping a possibly-real one gives valid SAS a bogus rc 1 — which is the exact
  failure the epic exists to remove.** So: `LINGUISTIC` leaves the gap arm because
  Procedures Guide p.2415 *excludes* it from the system option; FILENAME `TEMP`
  and `DDE` STAY at rc 2 with a note, despite zero grep hits across all eight
  volumes, because they are real device types documented in a volume we do not
  have (SAS Global Statements / the host companions) — absence from `docs/` is not
  absence from SAS. Corollary, and the reason "did I miss any?" is only half the
  check: §5d's SORTSEQ guard was wrong in BOTH DIRECTIONS IN THE SAME SEVEN LINES
  — it omitted four documented values *and* admitted one the doc excludes. Pair
  this with the tick397j predictor (what makes a catch-all splittable is whether
  the doc enumerates it in ONE PLACE) and with the re-derivation rule: a list
  closed against a doc must be re-derived from the doc IN FULL, never assembled
  from the values that came to mind. Three devs have now independently re-derived
  a count they were handed and each found more.
- D-017 **A STDOUT DIFFERENTIAL MUST CLEAN THE TREE BETWEEN PASSES** (2026-07-29
  tick398, promoted from @coder-ex's tick397j slice note where it would have been
  lost). The differential — run every `tests/**/*.sas` on a baseline binary, then on
  the patched one, diff the two stdout sets — is now the standard proof that a change
  moved nothing it should not have, and several devs run it per landing. It has a
  built-in false positive: **fixtures that WRITE FILES leave residue, so the second
  pass reads the FIRST pass's output and reports a mover that is not one.** @coder-ex's
  1900-file run first showed FOUR (`append_charwidth`, `bug_filenamemidstep`,
  `datasets_delete_disk`, `libname_readarms`); re-run individually with the tree
  cleaned between passes, TRUE MOVERS WERE ZERO. So: clean between passes, and treat
  any mover whose fixture writes a file as unproven until re-run in isolation. The
  failure mode is the dangerous direction — it manufactures phantom regressions, which
  costs a dev its whole budget chasing them, and worse, teaches the next reader that
  the differential cries wolf.
  **AMENDMENT (tick424, QA): A DIFFERENTIAL MUST REPRODUCE THE RUNNER'S WORKING
  DIRECTORY, NOT JUST ITS FILE LIST.** QA's first pass ran each fixture with cwd set
  to the fixture directory; **45 fixtures use repo-root-relative paths** and silently
  took an error path instead of exercising their subject. The comparison stayed
  VALID — both binaries behaved identically — but coverage was quietly weaker over
  those 45, which is the failure mode a clean result cannot show you. Re-run with the
  correct cwd: one mover, already accounted for. Worth keeping about the METHOD: QA
  reached this by forming the WRONG hypothesis first (sibling residue, i.e. D-017
  itself) and testing it — residue explained two of three observations, cwd explained
  all three. A hypothesis that explains MOST of the evidence is the one most likely to
  stop a search early.
  **SECOND AMENDMENT (tick436, QA): ONE PROGRAM PER CASE, OR AN ERRHALT WILL EAT YOUR
  ANSWERS.** QA's first MODIFY-audit run put ten probe cases in one program; an errhalt
  on case C put the run into syntax-check mode and **silently skipped cases D through
  G**, so it had four fewer answers than it believed. Restructured to one program per
  case, each with a fresh library, every result read back by a SEPARATE PROCESS — 33
  cases. The general rule: **a probe harness whose own failure mode is SILENCE will
  report success on work it never did.** That is the same shape as the cwd amendment
  above and as D-021: the dangerous harness bug is not the one that cries wolf, it is
  the one that quietly narrows coverage while the summary still reads clean. Corollary
  for anything that measures stored data: read it back from a separate process, because
  a listing produced by the same run is not evidence about a file.
  **THIRD AMENDMENT (tick438, QA): A HARNESS THAT FILTERS DIAGNOSTICS MANUFACTURES
  "SILENT" FINDINGS, exactly as one that BATCHES cases manufactures missing ones —
  and BOTH present as an ABSENCE.** QA's scope-audit rig summarised stderr with
  `grep -E 'ERROR|UNSUPPORTED'`. Two PROC SQL cases therefore looked SILENT
  (`update a set x = "notanumber"` replacing a real value with missing at rc 0), and
  it was one step from filing two silent-data-destruction findings. The unfiltered
  stream carried `NOTE: Invalid numeric data, 'notanumber'` — both CONFORMANT, since
  invalid numeric data in SAS is a NOTE plus missing at rc 0. **Rule: when a finding's
  evidence is "nothing was reported", check the RAW stream before believing it.** Two
  harness bugs in two consecutive audits, both signalled by absence — which is the
  pattern worth internalising: our diagnostics live on stderr and our comparisons
  mostly read stdout, so absence is the cheapest thing for a harness to fake.
  **FOURTH AMENDMENT (tick444, QA): WHEN AUDITING A RULE, USE THE RULE'S OWN
  PREDICATE — NOT AN APPROXIMATION OF IT.** QA's ambiguous-marker audit grepped
  `expect-rc` and reported two offenders, **one of them in its own prose**; the
  harness's marker is `expect-rc:` WITH THE COLON, so both were false. Re-run with
  the rule's actual predicate: zero. That is the THIRD time in one session that QA's
  own measurement pattern, rather than the code, produced a finding — the other two
  being the cwd and the filtered-stderr amendments above. Taken together they are one
  lesson: **an audit is a program, and its bugs look exactly like results.** Anything
  a sweep reports should be reproducible by the checked thing's own definition, not by
  a grep that resembles it.
  **AND A STANDING FACT ABOUT BASELINES (tick444): `origin/main` IS ROUTINELY INSIDE
  THE RANGE A SWEEP NEEDS TO AUDIT.** Three consecutive sweeps found the pushed tip
  sitting within the wave under audit, because pushes here are BATCHED every 20-30
  commits while landings are continuous. A sweep that takes `origin/main` as its
  baseline therefore compares a couple of commits instead of twenty. **The baseline to
  use is the head of the PREVIOUS sweep** — no gap, no double coverage — and it must be
  verified an ancestor with `merge-base --is-ancestor` rather than assumed.
- D-015a **AN UNDATED RESTRICTION IS NOT EVIDENCE AGAINST A DATED FEATURE
  STATEMENT** (2026-07-29 tick409, offered by @coder-f4 as a D-015 corollary while
  REVERTING ITS OWN LANDED COMMIT from two ticks earlier). D-015 says do not
  implement what the 9.4 reference does not contain. This is the other edge of the
  same blade: the volumes describe a product that CHANGED ACROSS MAINTENANCE
  RELEASES, and they mark the additions with an inline date ("Starting in the third
  maintenance release of SAS 9.4, you can specify linguistic collation ... by
  specifying the SORTSEQ=LINGUISTIC system option", Procedures Guide printed p.2403,
  manager-verified) while leaving the superseded prose in place undated (p.2415's
  Restrictions line, which says the opposite). **The word that settles a conflict
  like this is a DATE, not a modality** — "starting in" says the capability was
  ADDED, so the undated text describes the older product. The Statements Ref front
  matter documents this `SAS 9.4M6` notation, so it is the volumes' own convention,
  not an inference. Practical rule: before resting a verdict on a Restrictions or
  "not available" line, grep the surrounding chapter for a dated sentence about the
  same feature — twice here it was two pages away, in the same chapter.
  **This is the FOURTH distinct way a citation has been wrong in the rc epic —
  wrong page, wrong volume, wrong site, now wrong VINTAGE — and the only one that
  page-marker discipline cannot catch.**
- D-016 A TRACKER STATE IS NOT AN ACHIEVEMENT — verify a phase actually MOVED in the
  cycle before claiming it in release notes (2026-07-25, caught by the user):
  the v0.6.0 draft listed "Phase F is complete" as a headline highlight. It is a true
  statement — 468 implemented / 147 truly-infeasible / 0 unticked — but the tracker read
  **468/0/147 at v0.4.0, at v0.5.0 and at v0.6.0**: it had not changed in two releases.
  The manager had *discovered* the completeness mid-cycle (by counting the tracker for
  the first time) and wrote the discovery up as if it were the cycle's work. **Rule: for
  any phase/metric claimed in release notes, diff it against the PREVIOUS TAG
  (`git show v<prev>:<tracker>`) and quote the delta, not the absolute.** Phase G was
  the one that actually moved this cycle: 158/204 -> 185/205. Corollary: a git tag
  annotation cannot be corrected without force-moving a pushed tag, which this project
  does not do — so fix the GitHub release body and state the discrepancy openly.
