data lb;
  length usubjid $4;
  input usubjid $ aval;
  datalines;
S01 5.0
S02 .
S03 -2.0
S04 8.0
S05 .
;
run;
proc sort data=lb out=sorted; by aval; run;
proc print data=sorted noobs; run;
