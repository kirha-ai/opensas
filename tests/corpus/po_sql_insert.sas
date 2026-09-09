data ae;
  length usubjid $4 aeterm $10;
  input usubjid $ aeterm $;
  datalines;
S01 Headache
S02 Nausea
;
run;
proc sql;
  insert into ae values('S03', 'Fatigue') values('S03', 'Dizziness');
quit;
data _null_;
  n = &sqlobs;
  put "inserted=" n;
run;
proc print data=ae noobs; run;
