data have;
  input g x;
  datalines;
1 10
2 30
1 20
2 40
;
run;

proc sql;
  create table s as
    select g, sum(x) as sx, count(*) as n
    from have
    group by g;
quit;

data _null_;
  set s;
  put "g=" g " sum=" sx " n=" n;
run;
