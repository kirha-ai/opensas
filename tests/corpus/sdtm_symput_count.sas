/* Record count into a macro var, reused as a denominator */
data ex; input USUBJID $ DOSE; datalines;
01-001 50
01-002 100
01-003 75
;
run;
data _null_;
  set ex end=last;
  if last then call symputx("nrec", _n_);
run;
data pct;
  set ex;
  share = round(100 / &nrec, 0.1);
run;
proc print data=pct; var USUBJID share; run;
