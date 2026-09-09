data d;
  input id v;
  datalines;
1 10
2 50
3 30
;
run;

proc sql;
  create table hi as
    select id, v from d
    where v > (select avg(v) from d);
quit;

data _null_;
  set hi;
  put "id=" id " v=" v;
run;
