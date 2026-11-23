/* expect-rc: 1 */
/* An unequally spaced endpoint list should produce a specific SAS diagnostic. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x @@;
  datalines;
0 1 1 2 2 2 3 3 4
;
run;

proc univariate data=sample;
  var x;
  histogram x / endpoints=0 1 3 4 noplot;
run;
