/* Running cumulative + max dose per subject (RETAIN accumulators) */
data ex;
  input USUBJID $ EXDY EXDOSE;
  datalines;
01-001 1 50
01-001 8 60
01-001 15 40
01-002 1 75
01-002 8 25
;
run;
proc sort data=ex; by USUBJID EXDY; run;
data acc;
  set ex;
  by USUBJID;
  retain cumdose maxdose;
  if first.USUBJID then do;
    cumdose = 0;
    maxdose = 0;
  end;
  cumdose = cumdose + EXDOSE;
  maxdose = max(maxdose, EXDOSE);
run;
proc print data=acc; var USUBJID EXDY cumdose maxdose; run;
