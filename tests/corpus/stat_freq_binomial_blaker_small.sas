/* Obtain the Blaker interval for two events in seven trials. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input event n;
  datalines;
0 5
1 2
;
run;

proc freq data=sample;
  weight n / zeros;
  tables event / binomial(level="1" cl=blaker) alpha=.10;
run;
