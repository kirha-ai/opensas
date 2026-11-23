/* Both margins have two levels; the low count and zero corner are deliberate. */
options nodate nonumber;
data sample;
  input r c n;
  datalines;
1 1 0
1 2 1
2 1 3
2 2 1
;
run;
proc freq data=sample;
  weight n / zeros;
  tables r*c / fisher;
run;
