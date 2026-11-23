/* Both shape parameters are known; use a non-unit support. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x @@;
  datalines;
0.12 0.23 0.31 0.48 0.52 0.76 0.87 1.03 1.29 1.36 1.70 2.28 2.74 3.52 4.85 6.21
;
run;

proc univariate data=sample;
  var x;
  histogram x / beta(theta=0 sigma=8 alpha=2 beta=4) noplot;
run;
