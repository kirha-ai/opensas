/* GAP-varorder-assignset: EVERY statement before the SET establishes its
   variables at first mention, not just RETAIN and the sum statement — Language Reference: Concepts
   printed p.47, a variable's "position in observation is determined by the
   order in which the variables are defined in the DATA step". So
   `s = "hi"; y = 1; set a;` gives s y x b, matching the already-correct
   control `retain z 1; set a;` -> z x b (report 2); the two are the same rule
   and are pinned together so they cannot drift apart again.
   Report 3 pins the same order in an exported CSV header — PDV order is
   user-visible there too, not only through PROC PRINT.
   Report 4 is the shape a statement-KIND scanner cannot reach: targets nested
   behind IF/ELSE and inside a DO body still precede the SET textually, so they
   still own the earlier slots (w u i c x b). The fix is ONE declare walk split
   at the input statement, so nesting costs nothing.
   Report 5 is the over-hoist control: with the SET FIRST, nothing moves ahead
   of it (x b p) — the rule is textual position, not "assignments win".
   KNOWN GAP, deliberately not closed here: a variable named only on the RHS
   (`pre = v; set a;`, v coming from a) takes no slot at the RHS mention — see
   the declareVars ponytail. SAS orders v second; opensas leaves it at the SET.
   That is one rule for the whole step (an RHS read never declares, so a
   genuinely undefined one stays a NOTE and not a phantom column, GH#75) and it
   is pinned as-is by bug_prefixmergewipe. */
data a; x = 1; b = 2; run;
data t1; s = "hi"; y = 1; set a; run;
proc print data=t1; run;
data t2; retain z 1; set a; run;
proc print data=t2; run;
proc export data=t1 outfile="tests/corpus/includes/voas_t1.csv" dbms=csv replace; run;
data r;
  infile "tests/corpus/includes/voas_t1.csv" truncover;
  length line $40;
  input line $char40.;
run;
proc print data=r noobs; run;
data t4;
  if _n_ = 1 then w = 9; else u = 8;
  do i = 1 to 2; c = i; end;
  set a;
run;
proc print data=t4; run;
data t5; set a; p = 7; run;
proc print data=t5; run;
