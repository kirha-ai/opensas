data ae;
  length usubjid $4;
  input usubjid $ aeterm $;
  datalines;
S01 Headache
S01 Nausea
S01 Fatigue
S02 Headache
S03 Headache
S03 Rash
;
run;
proc sql;
  create table multi as select usubjid, count(*) as n_ae
    from ae group by usubjid having count(*) >= 2;
quit;
proc print data=multi noobs; run;
