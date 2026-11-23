/* Tied ranks use the integer part of FREQ; a subunit and missing frequency drop out. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x y n;
  datalines;
1 8 2.9
2 1 3
2 4 1
3 6 .8
4 4 .
5 5 2
;
run;

proc corr data=sample spearman kendall;
  var x y;
  freq n;
run;
