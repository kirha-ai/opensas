/* expect-rc: 1 */
/* The largest observation equals the fixed upper support endpoint. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x @@;
  datalines;
.1 .2 .3 .4 .5 .6 .7 .8 .9 1
;
run;

proc univariate data=sample;
  var x;
  histogram x / beta(theta=0 sigma=1) noplot;
run;
