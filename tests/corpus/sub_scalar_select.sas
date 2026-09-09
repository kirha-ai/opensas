data dm; length usubjid $4; input usubjid $ age; datalines;
S01 45
S02 60
S03 30
S04 70
;
run;
proc sql;
  create table t as select usubjid, age, (select max(age) from dm) as maxage from dm;
quit;
proc print data=t noobs; run;
