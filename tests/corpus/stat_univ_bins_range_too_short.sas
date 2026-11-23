/* Specify an otherwise regular interval grid that omits observations. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x @@;
  datalines;
0 1 1 2 2 2 3 3 4
;
run;

proc univariate data=sample;
  var x;
  histogram x / endpoints=1 2 3 noplot;
run;
