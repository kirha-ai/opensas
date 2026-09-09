/* Compute a mean in a DATA step, push to a macro var, filter above it downstream */
data lb; input AVAL; datalines;
10
20
30
40
;
run;
data _null_;
  set lb end=last;
  sm + AVAL;
  n + 1;
  if last then call symputx("avg", sm / n);
run;
data above;
  set lb;
  where AVAL > &avg;
run;
proc print data=above; run;
