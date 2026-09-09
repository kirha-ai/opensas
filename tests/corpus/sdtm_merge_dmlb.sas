/* Merge demographics with labs by subject (DATA step MERGE + BY) */
data dm;
  input USUBJID $ SEX $ AGE;
  datalines;
01-001 M 45
01-002 F 52
01-003 M 38
;
run;
data lb;
  input USUBJID $ LBSTRESN;
  datalines;
01-001 30
01-002 45
01-003 55
;
run;
proc sort data=dm; by USUBJID; run;
proc sort data=lb; by USUBJID; run;
data merged;
  merge dm lb;
  by USUBJID;
run;
proc print data=merged; run;
