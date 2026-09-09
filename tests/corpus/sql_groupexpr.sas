data d; input v @@; datalines;
5 15 25 8 30
;
run;
proc sql;
  create table g as
    select case when v>10 then "hi" else "lo" end as b, count(*) as n
    from d group by (v>10);
quit;
data _null_;
  set g;
  put "grp " b= n=;
run;
