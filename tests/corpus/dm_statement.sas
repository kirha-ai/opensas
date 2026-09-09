/* D-022 (BUG-xstmtsilentnoop): DM stays inert everywhere, but the FILE/OUT
   redirection form is observable and NOTEs — see x_dm_note.sas. Read the
   three statements below with that split in mind:
     line 1  open-code windowing commands  → silent, correct (nothing to observe;
             "output" is the OUTPUT WINDOW, not an `out` redirection — the
             WHOLE-WORD predicate is what keeps this line quiet, and it is the
             negative control GH#83 part 2 must not regress).
     mid-step `dm log 'clear' editor;`     → silent, correct (windowing).
     last line, OPEN-CODE `dm … file …;`   → NOTEs (GH#83 part 2 wired the
             open-code segmenter to the same D-022 emitter). The NOTE is
             stderr, so this golden stays byte-identical; its text and
             exactly-once emission are pinned by the captured-reporter test in
             src/main.zig. */
dm 'log;clear;output;clear';
data _null_;
  dm log 'clear' editor;
  msg = "step runs after dm";
  put msg;
run;
dm log "file 'out.log' replace;";
