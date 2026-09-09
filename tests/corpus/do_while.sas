data _null_;
  n = 1;
  do while (n <= 16);
    n = n * 2;
  end;
  put "n=" n;
run;
