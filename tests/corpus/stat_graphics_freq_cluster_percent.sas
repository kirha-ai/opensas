/* Grouped bars for a rectangular table with unequal row totals. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input r c n;
  datalines;
1 1 3
1 2 1
1 3 0
2 1 0
2 2 2
2 3 2
;
run;

ods listing gpath="%sysfunc(pathname(work))";
ods graphics on;
proc freq data=sample;
  weight n / zeros;
  tables r*c / plots(only)=freqplot(twoway=cluster scale=percent);
run;
ods graphics off;
