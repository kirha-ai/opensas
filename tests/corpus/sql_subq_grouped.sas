data d;
  input g $ v;
  datalines;
A 1
A 2
A 3
B 1
B 2
C 1
;
run;
proc sql;
  create table r as
  select g, v from d
  where g in (select g from d group by g having count(*) >= 2)
  order by g, v;
quit;
proc print data=r noobs; run;
