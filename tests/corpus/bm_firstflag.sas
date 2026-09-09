data vs; length subjid $4 visit $4; input subjid $ visit $ sbp; datalines;
S001 SCR 130
S001 BL 128
S001 W4 125
S002 SCR 140
S002 BL 138
;
run;
data _null_;
  set vs;
  by subjid;
  blflag = first.subjid;
  put subjid visit "sbp=" sbp "baseline=" blflag;
run;
