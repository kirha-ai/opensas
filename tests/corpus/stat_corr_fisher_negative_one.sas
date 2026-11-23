/* Exactly reversed ranks give the negative boundary of Fisher inference. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x y;
  datalines;
1 5
2 4
3 3
4 2
5 1
;
run;

proc corr data=sample spearman fisher;
  var x y;
run;
