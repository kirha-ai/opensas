/* Observe OUTTABLE variable names and labels, then one row per analysis variable per site. */
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

proc univariate data=sample noprint outtable=summ;
  by site;
  var x y;
run;
proc contents data=summ out=columns(keep=varnum name type length label format) noprint; run;
proc sort data=columns; by varnum; run;
proc print data=columns noobs;
  var varnum name type length format label;
run;
proc print data=summ noobs;
  var site _var_ _nobs_ _mean_ _median_;
run;
