data t;
  input r $ c $ n;
  datalines;
r1 c1 2
r1 c2 1
r2 c1 1
r2 c2 2
;
run;

proc freq data=t;
  weight n;
  tables r*c;
run;
