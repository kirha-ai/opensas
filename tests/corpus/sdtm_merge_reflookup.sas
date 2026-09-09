/* Add a treatment label from a reference table (MERGE BY code) */
data ex;
  input USUBJID $ TRTCD;
  datalines;
01-001 1
01-002 2
01-003 1
;
run;
data trtref;
  input TRTCD TRTLBL $12.;
  datalines;
1 ACTIVE
2 PLACEBO
;
run;
proc sort data=ex; by TRTCD; run;
proc sort data=trtref; by TRTCD; run;
data labeled;
  merge ex(in=a) trtref;
  by TRTCD;
  if a;
run;
proc sort data=labeled; by USUBJID; run;
proc print data=labeled; var USUBJID TRTCD TRTLBL; run;
