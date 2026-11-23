/* Suppress plotting when the observation count exceeds MAXPOINTS. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x y z n;
  datalines;
1 8 4 1
2 6 1 2
2 6 5 1
3 2 2 1
4 5 6 3
5 3 2 1
6 1 5 2
8 4 8 1
9 1 3 1
;
run;

ods listing gpath="%sysfunc(pathname(work))";
ods graphics on;
proc corr data=sample plots(maxpoints=3)=scatter;
  var x y;
run;
ods graphics off;
