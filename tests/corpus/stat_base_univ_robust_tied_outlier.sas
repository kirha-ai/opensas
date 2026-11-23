/* Robust scale estimates with repeated values and one extreme outlier. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x @@;
  datalines;
1 1 2 2 3 3 4 4 80
;
run;

ods select RobustScale;
proc univariate data=sample robustscale;
  var x;
run;
ods select all;
