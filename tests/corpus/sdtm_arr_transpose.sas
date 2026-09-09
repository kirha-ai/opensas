/* Wide-to-long by walking two parallel arrays (values + names) */
data vs;
  input USUBJID $ SBP DBP HR;
  datalines;
01-001 120 80 72
01-002 130 85 68
;
run;
data long;
  set vs;
  array v{3} SBP DBP HR;
  array pn{3} $3 _temporary_ ("SBP" "DBP" "HR");
  length param $3;
  do i = 1 to 3;
    param = pn{i};
    aval = v{i};
    output;
  end;
  keep USUBJID param aval;
run;
proc print data=long; run;
