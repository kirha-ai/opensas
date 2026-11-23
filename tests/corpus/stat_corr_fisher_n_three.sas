/* At N=3 the usual Fisher standard error has no degrees of freedom. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x y;
  datalines;
1 1
2 3
3 2
;
run;

proc corr data=sample fisher;
  var x y;
run;
