data a;
  input x;
  datalines;
1
2
3
;
run;

data b;
  input x;
  datalines;
2
3
4
;
run;

proc sql;
  create table t as select x from a intersect select x from b;
quit;

data _null_;
  set t;
  put "x=" x;
run;
