/* Flag the peak reading(s) using a data-derived max macro var */
data vs; input USUBJID $ AVAL; datalines;
01-001 120
01-002 145
01-003 118
01-004 145
;
run;
data _null_;
  set vs end=last;
  retain mx;
  mx = max(mx, AVAL);
  if last then call symputx("peak", mx);
run;
data flagged;
  set vs;
  ispeak = (AVAL = &peak);
run;
proc print data=flagged; var USUBJID AVAL ispeak; run;
