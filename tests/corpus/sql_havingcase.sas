data d; input g $ v; datalines;
a 9
b 3
c 10
;
run;
proc sql;
  create table r as select g, sum(v) as s from d group by g
    having case when sum(v)>5 then 1 else 0 end = 1;
quit;
data _null_;
  set r;
  put "r " g= s=;
run;
