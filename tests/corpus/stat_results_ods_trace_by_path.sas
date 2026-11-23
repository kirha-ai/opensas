/* Trace the object paths for two BY groups while selecting the same output object. */
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

ods trace on;
ods select PearsonCorr;
proc corr data=sample ;
  by site;
  var x y;
run;
ods select all;
ods trace off;
