data dm; length usubjid $4; input usubjid $ age; datalines;
S01 45
S02 60
S03 30
S04 70
;
run;
data ae; length usubjid $4; input usubjid $ aeterm $; datalines;
S01 Headache
S02 Nausea
S04 Rash
;
run;
proc sql;
  create table t as select usubjid, age from dm where usubjid not in (select usubjid from ae);
quit;
proc print data=t noobs; run;
