data vs;
  input region subj sbp;
  datalines;
1 1 120
1 2 140
2 3 110
2 4 150
;
run;
proc sql;
  create table above_region_avg as
    select subj, sbp from vs v
    where sbp > (select avg(sbp) from vs where region = v.region);
quit;
proc print data=above_region_avg noobs; run;
