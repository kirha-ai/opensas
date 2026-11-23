/* All observations are events; the complementary level has zero weight. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input event n;
  datalines;
0 0
1 5
;
run;

proc freq data=sample;
  weight n / zeros;
  tables event / binomial(level="1" p=.25);
  exact binomial;
run;
