/* Multi-key sort: arm, then subject, then descending visit */
data vs;
  input ARM $ USUBJID $ VISITNUM AVAL;
  datalines;
DRUG 01-002 2 130
DRUG 01-001 1 120
DRUG 01-001 3 118
PLACEBO 01-003 1 140
DRUG 01-001 2 122
;
run;
proc sort data=vs;
  by ARM USUBJID descending VISITNUM;
run;
proc print data=vs; run;
