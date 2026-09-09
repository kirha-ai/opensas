data dm; length usubjid $4; input usubjid $; datalines;
S01
S02
S03
S04
;
run;
data lb; length usubjid $4; input usubjid $ aval; datalines;
S01 8
S02 45
S03 12
S04 60
;
run;
proc sql;
  create table flagged as select usubjid from dm
    where usubjid in (select usubjid from lb where aval > 40);
quit;
proc print data=flagged noobs; run;
