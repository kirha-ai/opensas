/* Capture the complete kernel grid, its bandwidth and its proportion scale. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x @@;
  datalines;
0.12 0.23 0.31 0.48 0.52 0.76 0.87 1.03 1.29 1.36 1.70 2.28 2.74 3.52 4.85 6.21
;
run;

proc univariate data=sample;
  var x;
  histogram x / kernel(k=triangular c=1) vscale=proportion outkernel=curve noplot;
run;
proc print data=curve noobs;
  format _numeric_ best16.;
run;
