data _null_;
  do i = 1 to 2;
    do j = 1 to 2;
      put "i=" i " j=" j;
    end;
  end;
run;
