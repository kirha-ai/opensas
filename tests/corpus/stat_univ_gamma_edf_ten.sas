/* Ten observations are just at the estimated gamma EDF threshold. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x @@;
  datalines;
1 2 3 4 5 6 8 10 13 17
;
run;

proc univariate data=sample;
  var x;
  histogram x / gamma noplot;
run;
