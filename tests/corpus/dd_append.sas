data base_ae;
  length usubjid $4 aeterm $10;
  input usubjid $ aeterm $;
  datalines;
S01 Headache
S02 Nausea
;
run;
data new_ae;
  length usubjid $4 aeterm $10;
  input usubjid $ aeterm $;
  datalines;
S03 Fatigue
;
run;
proc datasets library=work nolist;
  append base=base_ae data=new_ae;
quit;
proc print data=base_ae noobs; run;
