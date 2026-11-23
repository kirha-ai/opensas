/* Fractional cell weights distinguish valid frequency output from availability of exact tests. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input r c n;
  datalines;
1 1 1.4
1 2 2
2 1 3
2 2 1.6
;
run;

proc freq data=sample;
  weight n / zeros;
  tables r*c;
  exact fisher;
run;
