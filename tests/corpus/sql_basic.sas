data have;
  input age;
  datalines;
30
20
40
;
run;

proc sql;
  create table s as
    select count(*) as n, sum(age) as total, avg(age) as m
    from have;
quit;

data _null_;
  set s;
  put "n=" n " total=" total " avg=" m;
run;
