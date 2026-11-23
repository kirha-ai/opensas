/* Print missing frequencies while excluding them from percentage denominators. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input r c n;
  datalines;
1 1 2
1 2 1
2 1 1
. 2 3
2 . 4
;
run;

proc freq data=sample;
  weight n / zeros;
  tables r*c / missprint;
run;
