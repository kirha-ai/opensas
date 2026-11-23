/* Capture the gamma quantile scale and the rendered reference line. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x @@;
  datalines;
0.12 0.23 0.31 0.48 0.52 0.76 0.87 1.03 1.29 1.36 1.70 2.28 2.74 3.52 4.85 6.21
;
run;

ods listing gpath="%sysfunc(pathname(work))";
ods graphics on;
ods output QQPlot=qqdata;
proc univariate data=sample;
  var x;
  qqplot x / gamma(alpha=2 sigma=1);
run;
ods output close;
proc print data=qqdata noobs;
run;
ods graphics off;
