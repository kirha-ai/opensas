/* QA tick322 F6 / NOTE-pagemidstep — the log-only inert globals (PAGE/SKIP,
   Language Reference: Concepts p.209) are accepted in open code and mid-PROC; the DATA-step parser
   now AGREES (D-014a, atGlobalStmt gains the isInertGlobalKw set). Pre-fix a
   mid-DATA-step `page;` fell through to parseAssign and died with the
   misleading "expected '=' in assignment", naming the wrong construct (same
   shape as NOTE-removenamedds). */
data d; x=1;
  page;
  skip;
run;
proc print data=d noobs; run;

/* positive control: `page = 5;` is a plain ASSIGNMENT (valid variable name) —
   the `=` guard keeps it out of the inert swallow. */
data e; page = 5; run;
proc print data=e noobs; run;
