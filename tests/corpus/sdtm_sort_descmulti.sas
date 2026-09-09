/* Multi-key sort with a DESCENDING key (arm asc, value desc) */
data vs; input ARM $ USUBJID $ AVAL; datalines;
DRUG 01-001 120
DRUG 01-002 145
PLACEBO 01-003 138
DRUG 01-004 130
PLACEBO 01-005 150
;
run;
proc sort data=vs;
  by ARM descending AVAL;
run;
proc print data=vs; run;
