/* Two OUTPUT statements request distinct summaries in one invocation. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  length site $8; label site="Study site" x="Baseline" y="Follow-up";
  input site $ x y;
  datalines;
A 1 3
A 2 1
A 5 4
B 3 2
B 4 6
B 7 5
;
run;

proc univariate data=sample noprint;
  var x;
  output out=centers mean=average;
  output out=spreads range=range;
run;
proc print data=centers noobs;
run;
proc print data=spreads noobs;
run;
