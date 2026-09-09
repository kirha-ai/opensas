data d;
  input dept $;
  datalines;
sales
sales
hr
it
it
it
;
run;

proc sql;
  create table t as select dept, count(*) as n from d group by dept order by count(*);
quit;

data _null_;
  set t;
  put "dept=" dept " n=" n;
run;
