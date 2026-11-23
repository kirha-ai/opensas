/* Three distinct missingness patterns distinguish pairwise from listwise sample sizes. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x y z;
  datalines;
1 9 .
2 4 2
. 1 7
4 . 5
5 5 8
8 3 1
;
run;

proc corr data=sample nomiss;
  var x y z;
run;
