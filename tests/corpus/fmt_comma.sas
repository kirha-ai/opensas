data _null_;
  x = 1234567.89;
  put "a=" x comma12.2;
  put "b=" x comma10.;
  y = -9876.5;
  put "c=" y comma12.1;
run;
