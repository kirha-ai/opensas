/* Capture normal P-P plot coordinates for ties as well as the rendered diagonal. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x @@;
  datalines;
-2 -1 -1 0 .5 .5 1 3
;
run;

ods listing gpath="%sysfunc(pathname(work))";
ods graphics on;
ods output PPPlot=ppdata;
proc univariate data=sample;
  var x;
  ppplot x / normal(mu=0 sigma=1);
run;
ods output close;
proc print data=ppdata noobs;
run;
ods graphics off;
