data d;
  input v @@;
  datalines;
2 4 6
;
run;
proc sql;
  select sum(v)+10 as sp from d;
  select max(v)-min(v) as rng from d;
  select sum(v)/count(*) as mean from d;
  select count(*)*100 as c100 from d;
quit;
