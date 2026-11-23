/* expect-rc: 1 */
/* Request a formatted binomial event level absent from the data. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input event $ n;
  datalines;
N 3
Y 2
;
run;

proc freq data=sample;
  weight n / zeros;
  tables event / binomial(level="X");
  exact binomial;
run;
