data ae;
  length usubjid $4 aeterm $12;
  input usubjid $ aeterm $;
  datalines;
S01 Headache
S02 Nausea
S03 HeadPain
S04 Dizziness
;
run;
proc sql;
  create table sel as select usubjid, aeterm from ae
    where usubjid in ('S01','S03','S99') and aeterm contains 'Head';
quit;
proc print data=sel noobs; run;
