/* Compare percentile definition 2 at both integral and fractional order-statistic indices. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x @@;
  datalines;
1 2 8 10 16 31
;
run;

proc univariate data=sample noprint pctldef=2;
  var x;
  output out=percentiles pctlpts=20 25 30 50 70 75 pctlpre=p;
run;
proc print data=percentiles noobs;
run;
