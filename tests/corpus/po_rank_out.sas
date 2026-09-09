data sc;
  length usubjid $4;
  input usubjid $ score;
  datalines;
S01 88
S02 72
S03 95
S04 60
;
run;
proc rank data=sc out=ranked(keep=usubjid rank) descending;
  var score;
  ranks rank;
run;
proc sort data=ranked out=ro; by usubjid; run;
proc print data=ro noobs; run;
