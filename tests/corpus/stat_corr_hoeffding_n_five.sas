/* Exactly five complete pairs, the first estimable sample size. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x y;
  datalines;
1 2
2 4
3 5
4 1
5 3
;
run;

proc corr data=sample hoeffding;
  var x y;
run;
