data lb;
  length usubjid $4;
  input usubjid $ aval;
  datalines;
S01 5.1
S02 12.4
S03 8.8
S04 15.0
;
run;
proc sort data=lb out=hi(where=(aval > 10)); by usubjid; run;
proc print data=hi noobs; run;
