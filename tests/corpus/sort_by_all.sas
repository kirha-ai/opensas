data a;
  x = 1; y = 2; output;
  x = 1; y = 2; output;
run;

proc sort nodupkey data=a;
  by _ALL_;
run;

data _null_;
  set a;
  put "x=" x " y=" y;
run;
