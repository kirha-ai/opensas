data dm; length usubjid $4; input usubjid $; datalines;
S01
S02
S03
;
run;
data ae; length usubjid $4; input usubjid $; datalines;
S01
S03
;
run;
proc sql;
  create table noae as select usubjid from dm
    where not exists (select 1 from ae where ae.usubjid=dm.usubjid);
quit;
proc print data=noae noobs; run;
