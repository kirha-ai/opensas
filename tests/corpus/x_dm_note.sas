/* BUG-xstmtsilentnoop (GH#83 part 1) — `data _null_; x "mkdir /tmp/d"; run;`
   produced ZERO output at rc 0 and no directory. X is deliberately NOT executed
   (settled by design; docs/sas9.4.ebnf's x_stmt carries no `(* opensas *)` for
   exactly that reason), but silence about it is the no-op D-002 forbids. Same
   for DM's log-REDIRECTION form (`dm log "file '…' replace;"`), where a
   downstream log check reads a file nobody wrote. Both now emit a NOTE
   (D-022) — the NOTE text is pinned by the captured-reporter test in
   src/parser.zig, because the corpus runner diffs stdout and diagnostics go to
   stderr.

   WHAT THIS FIXTURE PINS is the other half, and it is the half that has bitten
   this project before: a NOTE, NOT an ERROR. If anyone upgrades the severity,
   the step ERROR puts the run into syntax-check mode (BUG-errhalt) and SKIPS
   every later step — so this file's PROC PRINTs vanish and the rc leaves 0.
   That is the D-014 failure ("one legal statement silently kills the run"),
   and every program that legitimately carries an X statement pays it. No
   expect-rc marker: rc 0 is the assertion. */

data t;
  input id v;
  datalines;
1 10
2 20
;
run;

/* X mid-step — BOTH spellings. GH#83 part 2 (BUG-xstmtopencodesplit) settled
   the open question part 1 left here: the bare-name command form (`x mkdir
   "…";`) IS valid SAS (the quotes are optional) and stays accepted — the
   open-code recognizer (main.zig isXStmt) now agrees with this mid-step one
   instead of erroring on it between steps. The step must run to completion
   and the assignment after the X must take. */
data u;
  set t;
  x "mkdir /tmp/opensas_x_dm_note_never_created";
  w = v * 2;
run;
proc print data=u noobs; run;

data u2;
  set t;
  x mkdir "/tmp/opensas_x_dm_note_never_created2";
  w = v * 3;
run;
proc print data=u2 noobs; run;

/* DM redirection mid-step — noted, inert, step continues. */
data v;
  set t;
  dm log "file '/tmp/opensas_x_dm_note_never_written.log' replace;";
  w = v + 1;
run;
proc print data=v noobs; run;

/* The windowing DM commands stay SILENT (nothing outside the session to
   observe) and equally harmless — the `output` command must not be mistaken
   for an `out` redirection. */
data z;
  set t;
  dm 'log;clear;output;clear';
  w = v - 1;
run;
proc print data=z noobs; run;

/* ── GH#83 part 2: the OPEN-CODE half ── X in either spelling and DM's
   log-redirection form between steps now emit the SAME D-022 NOTE as their
   mid-step twins (the open-code sites are main.zig's, unreachable from a
   parser-only fix; the bare-name form even ERRORed rc 1 there before — the
   recognizer split). Still NOTEs, never ERRORs: the steps AROUND them run,
   which is what the final print asserts, and X still never executes (nothing
   named opensas_x_dm_note_open_* may appear on disk). The NOTE text itself is
   stderr — pinned by the captured-reporter tests in src/main.zig (open code)
   and src/parser.zig (mid-step); this file keeps pinning rc 0 + uninterrupted
   steps. The open-code windowing idiom stays silent: dm_statement.sas's first
   line is that negative control. */
x "mkdir /tmp/opensas_x_dm_note_open_never_created";
x mkdir "/tmp/opensas_x_dm_note_open_never_created2";
dm log "file '/tmp/opensas_x_dm_note_open_never_written.log' replace;";

proc print data=t noobs; run;
