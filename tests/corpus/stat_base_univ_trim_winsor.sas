/* Compare trimmed and Winsorized means on the same asymmetric tails. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x @@;
  datalines;
-5 1 1 2 3 4 7 40 75 90
;
run;

proc univariate data=sample trimmed=.2 winsorized=.2;
  var x;
run;
