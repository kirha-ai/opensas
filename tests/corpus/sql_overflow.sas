data d;
  input x;
  datalines;
1e308
1e308
;
run;

proc sql;
  select sum(x) as s from d;
quit;
