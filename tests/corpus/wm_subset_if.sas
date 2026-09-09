data vs;
  length usubjid $4;
  input usubjid $ sbp;
  datalines;
S01 118
S02 145
S03 132
S04 128
;
run;
data high;
  set vs;
  if sbp >= 130;
  flag = 1;
run;
proc print data=high noobs; run;
