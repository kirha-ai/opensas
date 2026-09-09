data _null_;
  x = input("1,234.5", comma8.);
  put "x=" x;
  d = input("15MAR2020", date9.);
  put "d=" d;
  n = input("3.14", 8.2);
  put "n=" n;
run;
