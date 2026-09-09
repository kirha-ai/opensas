data d;
  input g s $ r @@;
  datalines;
1 X 1  1 Y 0  . X 0  . X 1  2 Y 1  2 Y 0
;
run;

proc freq data=d;
  tables g*s*r;
run;

proc freq data=d;
  tables g*s*r / missing;
run;
