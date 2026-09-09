/* Merge three domains by subject (DM + LB + VS via MERGE BY) */
data dm; input USUBJID $ SEX $; datalines;
01-001 M
01-002 F
01-003 M
;
run;
data lb; input USUBJID $ ALT; datalines;
01-001 30
01-002 45
01-003 55
;
run;
data vs; input USUBJID $ SBP; datalines;
01-001 120
01-002 130
01-003 128
;
run;
proc sort data=dm; by USUBJID; run;
proc sort data=lb; by USUBJID; run;
proc sort data=vs; by USUBJID; run;
data all;
  merge dm lb vs;
  by USUBJID;
run;
proc print data=all; run;
