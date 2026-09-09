data vs; length subjid $4 visit $4; input subjid $ visit $ wt; datalines;
S001 V1 70
S001 V2 72
S001 V3 71
S002 V1 65
S002 V2 66
;
run;
data lastwt;
  set vs;
  by subjid;
  if last.subjid;
run;
proc print data=lastwt noobs; run;
