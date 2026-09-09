data lb; length usubjid $4; input usubjid $ aval; datalines;
S01 10
S01 30
S02 20
S02 60
;
run;
proc sql;
  create table above_own_mean as select usubjid, aval from lb l
    where aval > (select avg(aval) from lb where usubjid = l.usubjid);
quit;
proc print data=above_own_mean noobs; run;
