data _null_;
  array a{5} a1-a5 (10 20 30 40 50);
  total = 0;
  do i = 1 to 5;
    total = total + a{i};
  end;
  put "total=" total;
run;
