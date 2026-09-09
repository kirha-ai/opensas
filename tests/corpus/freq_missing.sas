data d;
  input g;
  datalines;
1
1
2
.
;
run;
proc freq data=d; tables g; run;
proc freq data=d; tables g / missing; run;
