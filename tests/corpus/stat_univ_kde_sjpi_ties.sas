/* A repeated central mass plus a distant observation tests the SJPI bandwidth selector. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x @@;
  datalines;
1 1 1 2 2 2 2 3 3 3 4 10
;
run;

proc univariate data=sample;
  var x;
  histogram x / kernel(c=sjpi) outkernel=curve noplot;
run;
proc print data=curve noobs;
  format _numeric_ best16.;
run;
