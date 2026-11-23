/* Horizontal cumulative frequency dots on a percentage scale. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input grade $ n;
  datalines;
C 3
A 1
B 2
;
run;

ods listing gpath="%sysfunc(pathname(work))";
ods graphics on;
proc freq data=sample order=data;
  weight n;
  tables grade / plots(only)=cumfreqplot(type=dotplot orient=horizontal scale=percent);
run;
ods graphics off;
