/* Render deviations from supplied unequal null proportions. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input r n;
  datalines;
1 2
2 7
3 1
;
run;

ods listing gpath="%sysfunc(pathname(work))";
ods graphics on;
proc freq data=sample;
  weight n / zeros;
  tables r / chisq(testp=(.2 .3 .5)) plots(only)=deviationplot;
run;
ods graphics off;
