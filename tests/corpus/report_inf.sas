data d;
  x = 1e400;
  y = 3;
run;

proc report data=d nowd;
  columns x y;
run;
