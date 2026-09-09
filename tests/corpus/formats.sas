data _null_;
  x = 3.14159;
  n = 1234.5;
  d = mdy(1, 1, 1960);
  put x 8.2;
  put n comma10.2;
  put d date9.;
  put d mmddyy10.;
run;
