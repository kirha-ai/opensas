data _null_;
  n = 1;
  do until (n > 100);
    n = n * 3;
  end;
  put "n=" n;
run;
