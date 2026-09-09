data vs; length usubjid $4 visit $4; input usubjid $ visit $ sbp; datalines;
S01 V1 120
S01 V2 118
S02 V1 130
S02 V2 128
;
run;
data tgt; length usubjid $4 visit $4; input usubjid $ visit $ target; datalines;
S01 V1 140
S01 V2 135
S02 V1 140
;
run;
proc sql;
  create table j as select vs.usubjid, vs.visit, sbp, target
    from vs inner join tgt on vs.usubjid=tgt.usubjid and vs.visit=tgt.visit;
quit;
proc print data=j noobs; run;
