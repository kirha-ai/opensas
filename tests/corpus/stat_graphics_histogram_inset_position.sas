/* Compare the plotted bars with exported counts and an explicitly labeled inset. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x @@;
  datalines;
0.12 0.23 0.31 0.48 0.52 0.76 0.87 1.03 1.29 1.36 1.70 2.28 2.74 3.52 4.85 6.21
;
run;

ods listing gpath="%sysfunc(pathname(work))";
ods graphics on;
proc univariate data=sample;
  var x;
  histogram x / endpoints=0 to 8 by 2 barlabel=count outhistogram=plotbins;
  inset n mean="Average" / position=nw;
run;
proc print data=plotbins noobs;
run;
ods graphics off;
