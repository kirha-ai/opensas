/* Interior ties reveal which bin owns its endpoint; both outer endpoints are present. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x @@;
  datalines;
0 .5 1 1 1.5 2 2 2 3 3 4
;
run;

proc univariate data=sample;
  var x;
  histogram x / endpoints=0 to 4 by 1 outhistogram=bins noplot;
run;
proc print data=bins noobs;
run;
