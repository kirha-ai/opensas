/* Use a lower endpoint just below a pile of ties; request fixed shape and free scale. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x @@;
  datalines;
1 1 1 1 1 1 1 20
;
run;

proc univariate data=sample;
  var x;
  histogram x / power(theta=.9999 sigma=est alpha=0.5) noplot;
run;
