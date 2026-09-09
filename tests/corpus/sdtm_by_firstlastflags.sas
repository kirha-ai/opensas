/* FIRST./LAST. flags mark the boundary rows of each subject's records */
data lb; input USUBJID $ VISITNUM AVAL; datalines;
01-001 1 30
01-001 2 40
01-001 3 35
01-002 1 50
01-002 2 55
;
run;
proc sort data=lb; by USUBJID VISITNUM; run;
data flagged;
  set lb;
  by USUBJID;
  ff = first.USUBJID;
  fl = last.USUBJID;
run;
proc print data=flagged; var USUBJID VISITNUM ff fl; run;
