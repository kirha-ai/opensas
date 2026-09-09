data dm; length usubjid $4 arm $8; input usubjid $ arm $; datalines;
S01 Active
S02 Placebo
S03 Active
;
run;
data lb; length usubjid $4; input usubjid $ aval; datalines;
S01 5.1
S02 7.3
S04 9.9
;
run;
proc sql;
  create table j as select dm.usubjid, arm, aval from dm left join lb on dm.usubjid=lb.usubjid;
quit;
proc print data=j noobs; run;
