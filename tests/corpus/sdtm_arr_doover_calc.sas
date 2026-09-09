/* Sum and mean of readings via DO OVER (implicit array index) */
data lb;
  input USUBJID $ r1 r2 r3 r4;
  datalines;
01-001 10 20 30 40
01-002 5 15 25 35
;
run;
data agg;
  set lb;
  array r{4} r1-r4;
  tot = 0;
  do over r;
    tot = tot + r;
  end;
  mean = tot / dim(r);
  keep USUBJID tot mean;
run;
proc print data=agg; run;
