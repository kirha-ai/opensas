/* Split labs into high/low datasets in one DATA step (data a b; + output x) */
data hi lo;
  input USUBJID $ AVAL;
  if AVAL >= 50 then output hi;
  else output lo;
  datalines;
01-001 30
01-002 60
01-003 45
01-004 75
;
run;
proc print data=hi; run;
proc print data=lo; run;
