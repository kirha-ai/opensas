/* Use fully specified normal parameters for EDF tests at tied values. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x @@;
  datalines;
-2 -1.5 -1 -.5 -.5 0 .25 .5 .75 1 1.5 2
;
run;

proc univariate data=sample;
  var x;
  histogram x / normal(mu=0 sigma=1) noplot;
run;
