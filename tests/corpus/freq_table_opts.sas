data d;
  input g $ @@;
  datalines;
a a b a b b b
;
run;
proc freq data=d;
  tables g / nopercent missing list;
run;
