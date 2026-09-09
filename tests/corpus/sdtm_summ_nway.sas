/* PROC SUMMARY NWAY output dataset (finest cross; _TYPE_/_FREQ_ auto-vars) */
data ex; input ARM $ USUBJID $ EXDOSE; datalines;
DRUG 01-001 50
DRUG 01-001 60
DRUG 01-002 100
PLAC 01-003 0
;
run;
proc summary data=ex noprint nway;
  class ARM;
  var EXDOSE;
  output out=tot sum=total mean=avg;
run;
proc print data=tot; run;
