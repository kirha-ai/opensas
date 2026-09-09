/* Post-baseline records via a where= dataset option on SET */
data lb;
  input USUBJID $ VISITNUM AVAL;
  datalines;
01-001 1 30
01-001 2 45
01-002 1 50
01-002 2 55
;
run;
data post;
  set lb(where=(VISITNUM > 1));
run;
proc print data=post; run;
