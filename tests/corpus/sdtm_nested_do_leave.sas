/* Inner-loop LEAVE stops each row at the first column past threshold */
data d;
  do i = 1 to 3;
    do j = 1 to 3;
      if j = 2 then leave;
      x = i * 10 + j;
      output;
    end;
  end;
  keep x;
run;
proc print data=d; run;
