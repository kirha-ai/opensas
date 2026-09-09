data dm; length usubjid $4 arm $8; input usubjid $ arm $; datalines;
S01 Active
S02 Placebo
;
run;
data lb; length usubjid $4; input usubjid $ aval; datalines;
S01 5.1
S02 7.3
;
run;
data vs; length usubjid $4; input usubjid $ sbp; datalines;
S01 120
S02 130
;
run;
proc sql;
  create table j as select dm.usubjid, arm, aval, sbp
    from dm inner join lb on dm.usubjid=lb.usubjid
            inner join vs on dm.usubjid=vs.usubjid;
quit;
proc print data=j noobs; run;
