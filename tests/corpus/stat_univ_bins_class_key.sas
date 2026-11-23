/* Compare comparative histogram grids for a compact first class and a widely spread second class. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input g $ x;
  datalines;
A 0
A 1
A 1
A 2
A 3
B 10
B 15
B 20
B 30
;
run;

proc univariate data=sample;
  class g;
  var x;
  histogram x / endpoints=key outhistogram=bins noplot;
run;
proc print data=bins noobs;
run;
