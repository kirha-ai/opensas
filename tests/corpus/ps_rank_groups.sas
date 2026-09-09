data sc;
  length usubjid $4;
  input usubjid $ score;
  datalines;
S01 55
S02 70
S03 62
S04 88
S05 91
S06 47
;
run;
proc rank data=sc out=tertile groups=3;
  var score;
  ranks tgrp;
run;
proc sort data=tertile out=t2; by usubjid; run;
proc print data=t2 noobs; run;
