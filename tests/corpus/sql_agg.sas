data have;
  input id v;
  datalines;
1 10
2 20
3 30
;
run;

proc sql;
  select sum(v) as total, avg(v) as mean
  from have;
quit;
