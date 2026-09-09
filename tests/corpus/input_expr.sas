data _null_;
  d = input("15JAN1960", date9.);
  y = input("1960-01-15", yymmdd10.);
  n = input("1,234", comma8.);
  put "d=" d " y=" y " n=" n;
run;
