/* Zero, negative and missing weights expose differences in N and variance divisor. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x y w;
  datalines;
1 5 1
2 2 -1
3 6 2
4 9 0
5 3 3
8 1 .
;
run;

proc corr data=sample cov ;
  var x y;
  weight w;
run;
