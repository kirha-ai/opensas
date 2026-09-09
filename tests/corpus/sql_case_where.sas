data d;
  input x;
  datalines;
5
15
25
;
run;

proc sql;
  create table t as
    select x from d
    where case when x < 10 then "lo" else "hi" end = "hi";
quit;

data _null_;
  set t;
  put "x=" x;
run;
