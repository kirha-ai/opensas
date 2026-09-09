data _null_;
  do i = 1 to 5;
    if i = 3 then leave;
    put "i=" i;
  end;
  put "done";
run;
