/* Wide-to-long: vitals columns to one row per measure (PROC TRANSPOSE var list) */
data vs;
  input USUBJID $ SBP DBP HR;
  datalines;
01-001 120 80 72
01-002 130 85 68
;
run;
proc sort data=vs; by USUBJID; run;
proc transpose data=vs out=long name=param;
  by USUBJID;
  var SBP DBP HR;
run;
proc print data=long; var USUBJID param COL1; run;
