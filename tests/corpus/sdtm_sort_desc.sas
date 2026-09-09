/* Rank subjects by value, highest first (PROC SORT descending) */
data vs;
  input USUBJID $ VSSTRESN;
  datalines;
01-001 120
01-002 145
01-003 118
01-004 132
;
run;
proc sort data=vs out=ranked;
  by descending VSSTRESN;
run;
proc print data=ranked; run;
