/* CTCAE-style grade from a lab ratio (nested IF-THEN-ELSE) */
data lb;
  input USUBJID $ LBSTRESN LBORNRHI;
  datalines;
01-001 45 40
01-002 130 40
01-003 38 40
01-004 210 40
;
run;
data graded;
  set lb;
  ratio = LBSTRESN / LBORNRHI;
  length grade $2;
  if ratio <= 1 then grade = "0";
  else if ratio <= 3 then grade = "1";
  else if ratio <= 5 then grade = "2";
  else grade = "3";
run;
proc print data=graded; var USUBJID LBSTRESN ratio grade; run;
