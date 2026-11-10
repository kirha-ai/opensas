/* GAP-univ-summary-complete: ID now labels the extreme observations. */
data d;
  x = 1;
run;

proc univariate data=d;
  id x;
  var x;
run;

proc print data=d;
run;
