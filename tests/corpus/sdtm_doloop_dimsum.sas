/* Sum and mean across array members with DO 1 TO DIM() */
data lb; input USUBJID $ r1 r2 r3 r4; datalines;
01-001 10 20 30 40
01-002 5 15 25 35
;
run;
data agg;
  set lb;
  array r{4} r1-r4;
  tot = 0;
  do i = 1 to dim(r);
    tot = tot + r{i};
  end;
  mean = tot / dim(r);
  keep USUBJID tot mean;
run;
proc print data=agg; run;
