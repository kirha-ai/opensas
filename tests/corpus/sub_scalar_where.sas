data dm; length usubjid $4; input usubjid $ age; datalines;
S01 45
S02 60
S03 30
S04 70
;
run;
proc sql;
  create table t as select usubjid, age from dm where age > (select avg(age) from dm);
quit;
proc print data=t noobs; run;
