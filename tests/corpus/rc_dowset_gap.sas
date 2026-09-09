/* GAP-gapsexitingone §5c — exec.zig's slice of the D-009 exit-code contract,
   pinned end-to-end through main's exit path (the in-source `D-009 §5c` tests
   pin exitCode(gapHit, hasErrors); only a fixture pins the PROCESS rc).

   `do i = 1 to n; set a; end;` is ordinary SAS 9.4 — the SET reads one
   observation per iteration. opensas models only the DOW (DO UNTIL/WHILE)
   shape, so refusing it is an opensas GAP: rc 2, "file an opensas issue",
   not rc 1 "fix your SAS". The message is unchanged; only the rc moved.

   The PROC PRINT above proves the guard DISCRIMINATES rather than rejecting
   every SET-in-a-DO: the DOW form still runs and produces its total.
   One error, last — a step ERROR trips syntax-check mode and skips every
   later step (BUG-errhalt), so anything below would silently not run.
   expect-rc: 2 */
data a;
  input x;
  datalines;
10
20
;
run;

data ok;
  do until (eof);
    set a end=eof;
    total + x;
  end;
run;

proc print data=ok noobs;
run;

data b;
  do i = 1 to 2;
    set a;
  end;
run;
