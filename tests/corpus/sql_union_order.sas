data a;
  input x;
  datalines;
3
1
;
run;
data b;
  input x;
  datalines;
4
2
;
run;

proc sql;
  create table u as
    select x from a
    union
    select x from b
    order by x;
quit;

data _null_;
  set u;
  put "x=" x;
run;
