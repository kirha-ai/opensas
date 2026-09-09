/* Route pooled records to per-domain datasets (multi-output by category) */
data ae vs lb;
  input DOMAIN $ USUBJID $ VAL;
  if DOMAIN = "AE" then output ae;
  else if DOMAIN = "VS" then output vs;
  else output lb;
  datalines;
AE 01-001 1
VS 01-001 120
LB 01-002 30
AE 01-002 2
;
run;
proc print data=ae; run;
proc print data=vs; run;
proc print data=lb; run;
