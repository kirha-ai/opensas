data _null_;
  total = 0;
  do i = 1 to 5;
    total = total + i;
  end;
  put "total=" total;
run;
