/* CDF steps at repeated values, with the vertical axis in proportions. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x @@;
  datalines;
1 1 2 2 2 3 4 4 6
;
run;

ods listing gpath="%sysfunc(pathname(work))";
ods graphics on;
proc univariate data=sample;
  var x;
  cdfplot x / vscale=proportion;
run;
ods graphics off;
