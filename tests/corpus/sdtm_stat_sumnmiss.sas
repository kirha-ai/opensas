/* N / NMISS / SUM with missing data present (PROC MEANS) */
data ex; input USUBJID $ DOSE; datalines;
01-001 50
01-002 .
01-003 100
01-004 75
01-005 .
;
run;
proc means data=ex n nmiss sum mean;
  var DOSE;
run;
