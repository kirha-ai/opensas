/* Overlapping continuous measurements in three ordinal groups give an interior estimate. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x g;
  datalines;
1 1
3 1
5 1
2 2
4 2
6 2
3 3
5 3
8 3
;
run;

proc corr data=sample polyserial;
  var x;
  with g;
run;
