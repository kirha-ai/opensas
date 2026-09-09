data d;
  input x;
  datalines;
1
2
2
3
3
3
;
run;

proc sql;
  create table u as select distinct x from d;
quit;

data _null_;
  set u;
  put "x=" x;
run;
