data _null_;
  do i = 1 to 4;
    if i = 2 then continue;
    put "i=" i;
  end;
run;
