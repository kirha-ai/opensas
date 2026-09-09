/* First non-missing onset date across candidate sources (COALESCE) */
data ae;
  input USUBJID $ dt1 dt2 dt3;
  datalines;
01-001 . 100 200
01-002 50 . 200
01-003 . . 300
;
run;
data resolved;
  set ae;
  firstdt = coalesce(dt1, dt2, dt3);
run;
proc print data=resolved; var USUBJID firstdt; run;
