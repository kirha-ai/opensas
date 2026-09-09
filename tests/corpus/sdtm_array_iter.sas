/* Mean of three readings per subject (ARRAY + iterative DO) */
data lb;
  input USUBJID $ v1 v2 v3;
  datalines;
01-001 10 20 30
01-002 40 50 60
;
run;
data means;
  set lb;
  array vv{3} v1-v3;
  total = 0;
  do i = 1 to 3;
    total = total + vv{i};
  end;
  avg = total / 3;
  keep USUBJID avg;
run;
proc print data=means; run;
