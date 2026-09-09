data dm; length usubjid $4; input usubjid $; datalines;
S01
S02
S03
;
run;
data ae; length usubjid $4; input usubjid $ aeterm $; datalines;
S01 Headache
S01 Nausea
S03 Rash
;
run;
proc sql;
  create table aecount as
    select dm.usubjid, count(ae.aeterm) as n_ae
    from dm left join ae on dm.usubjid=ae.usubjid
    group by dm.usubjid;
quit;
proc print data=aecount noobs; run;
