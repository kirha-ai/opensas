/* VS: baseline (first visit) vs last visit change per subject (RETAIN/BY/FIRST.LAST) */
data vs;
  input USUBJID $ VISITNUM VSSTRESN;
  datalines;
01-001 1 120
01-001 2 125
01-001 3 118
01-002 1 130
01-002 2 128
;
run;

proc sort data=vs; by USUBJID VISITNUM; run;

data chg;
  set vs;
  by USUBJID;
  retain baseline;
  if first.USUBJID then baseline = VSSTRESN;
  chg = VSSTRESN - baseline;
  if last.USUBJID then output;
  keep USUBJID VSSTRESN baseline chg;
run;

proc print data=chg; run;
