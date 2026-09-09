data lb; length usubjid $4; input usubjid $ aval; datalines;
S01 10
S01 30
S02 20
S02 60
S03 5
;
run;
proc sql;
  create table hi as select usubjid, mx
    from (select usubjid, max(aval) as mx from lb group by usubjid)
    where mx > 25;
quit;
proc print data=hi noobs; run;
