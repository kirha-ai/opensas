data _null_;
  do i = 1 to 5 while(i < 4);
    put "w i=" i;
  end;
  do j = 1 to 5 until(j >= 3);
    put "u j=" j;
  end;
run;
