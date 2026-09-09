/* BUG-linkacrossset (QA tick322 F1): a LINK whose call site and label block
   sit on OPPOSITE sides of the driving SET must run, not ERROR — Language Reference: Concepts p.485
   Table 20.3: LINK "return[s] control of the program to the next statement
   following the LINK statement", so the read still executes exactly once, in
   order. The classic idiom is the labelled subroutine block at the bottom of
   the step, called from before the SET (step o1); o2 is the reverse direction
   (label block before the SET, called after it); o3 is the in-range control
   (call and label both after the SET). A bare GOTO across the read stays a
   hard ERROR (pinned by the exec.zig "crosses the driving" unit test) — a
   GOTO can skip or re-run the read, a LINK cannot.
   COLUMN ORDER IS LOAD-BEARING in report 2 (mult k x, GAP-varorder-assignset):
   the PDV is built at COMPILE time in TEXTUAL order, so `mult = 10;` inside the
   labelled block owns the earlier slot even though it EXECUTES after the read —
   Language Reference: Concepts printed p.47, "position in observation is determined by the order in
   which the variables are defined in the DATA step". Reports 1 and 3 define
   mult/x after the SET and are unaffected. Do not "restore" k first. */
data a; input k @@; datalines;
1 2 3
;
run;
data o1;
  link init;
  set a;
  x = k * mult;
  return;
init:
  mult = 10;
  return;
run;
proc print data=o1; run;
data o2;
  goto go;
init:
  mult = 10;
  return;
go:
  set a;
  link init;
  x = k * mult;
run;
proc print data=o2; run;
data o3;
  set a;
  link addup;
  return;
addup:
  x = k + 100;
  return;
run;
proc print data=o3; run;
