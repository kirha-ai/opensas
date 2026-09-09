/* VS wide-to-long: three vitals columns become one row per measure (TRANSPOSE var) */
data vs; input USUBJID $ SYSBP DIABP PULSE; datalines;
01-001 120 80 72
01-002 135 88 68
;
run;
proc sort data=vs; by USUBJID; run;
proc transpose data=vs out=long name=vsparam;
  by USUBJID;
  var SYSBP DIABP PULSE;
run;
proc print data=long; var USUBJID vsparam COL1; run;
