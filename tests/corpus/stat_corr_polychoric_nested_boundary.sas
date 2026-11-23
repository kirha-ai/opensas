/* Nested ordinal levels with three occupied cells stress boundary convergence and information rank. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input r c n;
  datalines;
0 0 7
0 1 11
1 3 17
;
run;

proc corr data=sample polychoric(converge=1e-8);
  var r c;
  freq n;
run;
