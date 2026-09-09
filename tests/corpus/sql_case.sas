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
    select x, case when x < 10 then "lo" when x < 20 then "mid" else "hi" end as grp
    from d;
quit;

data _null_;
  set t;
  put "x=" x " grp=" grp;
run;
