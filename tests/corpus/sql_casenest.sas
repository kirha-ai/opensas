data d; input x @@; datalines;
5 15 25
;
run;
proc sql;
  create table r as
    select x, case when x<10 then "lo" else case when x<20 then "mid" else "hi" end end as b
    from d;
quit;
data _null_;
  set r;
  put "row " x= b=;
run;
