/* Retain the zero event count and check the Clopper-Pearson boundary. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input event n;
  datalines;
0 5
1 0
;
run;

proc freq data=sample;
  weight n / zeros;
  tables event / binomial(level="1" p=.25);
  exact binomial;
run;
