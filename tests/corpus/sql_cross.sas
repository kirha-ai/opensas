data a;
  input x;
  datalines;
1
2
;
run;
data b;
  input y;
  datalines;
10
20
;
run;

proc sql;
  create table c as
    select x, y from a, b
    order by x, y;
quit;

data _null_;
  set c;
  put "x=" x " y=" y;
run;
