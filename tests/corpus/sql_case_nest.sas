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
    select x,
      case when x < 20 then case when x < 10 then "lo" else "mid" end else "hi" end as g
    from d;
quit;

data _null_;
  set t;
  put "x=" x " g=" g;
run;
