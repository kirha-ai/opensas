data ae; input soc $ sev $; datalines;
A MILD
A SEV
B MILD
B MILD
;
run;
proc sql;
  create table x as
    select soc, sum(case when sev="MILD" then 1 else 0 end) as mild,
           avg(case when sev="MILD" then 1 else 0 end) as frac
    from ae group by soc;
quit;
data _null_;
  set x;
  put "grp " soc= mild= frac=;
run;
