data a;
  input x;
  datalines;
1
2
;
run;

data b;
  input x;
  datalines;
2
3
;
run;

proc sql;
  create table u as
    select x from a
    union
    select x from b;
quit;

data _null_;
  set u;
  put "x=" x;
run;
