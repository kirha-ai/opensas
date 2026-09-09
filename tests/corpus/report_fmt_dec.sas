data w;
  x = 1234.5;
run;

proc report data=w nowd;
  column x;
  define x / display format=comma10.2;
run;
