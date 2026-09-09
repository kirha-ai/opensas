%macro noop;
%mend noop;
data _null_;
  x = 10;
  %noop;
  y = x + 5;
  %noop;
  put "x=" x " y=" y;
run;
