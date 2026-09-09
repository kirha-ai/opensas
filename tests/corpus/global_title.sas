options nodate nonumber;
title "Vital Signs Report";
footnote "Confidential";

data vs;
  input pid sbp;
  datalines;
1 120
2 135
;
run;

proc print data=vs noobs;
run;
