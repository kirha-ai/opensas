/* Missing sorts before any value (PROC SORT ascending) */
data lb; input USUBJID $ AVAL; datalines;
01-001 30
01-002 .
01-003 10
01-004 20
;
run;
proc sort data=lb; by AVAL; run;
proc print data=lb; run;
